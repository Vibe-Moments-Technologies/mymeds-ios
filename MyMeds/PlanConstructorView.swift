import SwiftUI
import MyMedsCore
import DesignSystem

/// Конструктор плана (§12): 3 уровня над одним черновиком, выход всегда
/// развёрнутая сетка; уровень «Про» — параметры лекарства + предпросмотр
/// JSON medplan/1. DSL в хранилище не попадает (§5).
struct PlanConstructorView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Level: String, CaseIterable, Identifiable {
        case simple = "Простой"
        case mode = "Режим"
        case pro = "Про"
        var id: String { rawValue }
    }

    // Черновик (уровни переключаются над ним одним — progressive disclosure)
    @State private var level: Level = .simple

    @State private var medName = ""
    @State private var medUnit: DoseUnit = .mg
    @State private var form = ""
    @State private var intakeRule = ""
    @State private var cumulativeTargetText = ""
    @State private var weightText = ""
    @State private var notifyOn = false
    @State private var windowStart = 20
    @State private var windowEnd = 23
    @State private var windowInterval = 30

    @State private var planName = ""
    @State private var startsToday = true
    @State private var startEpoch = CivilDate.today().daysSinceEpoch
    @State private var durationDays = 28

    // Уровень «Режим»
    enum PatternKind: String, CaseIterable, Identifiable {
        case uniform = "Одна доза"
        case alternate = "Чередование"
        case segments = "Отрезки"
        var id: String { rawValue }
    }
    @State private var patternKind: PatternKind = .uniform
    @State private var uniformDoseText = "8"
    @State private var lowDoseText = "8"
    @State private var highDoseText = "16"
    @State private var segmentsText = "7:24;14:32"

    @State private var showJSON = false
    @State private var errorText: String?

    private var startDate: CivilDate { CivilDate(daysSinceEpoch: startEpoch) }
    private var dateRange: ClosedRange<Int> {
        let today = CivilDate.today().daysSinceEpoch
        return today...(today + 365)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                content
            }
            .navigationTitle("Новый план")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showJSON) { jsonPreviewSheet }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                levelPicker
                medSection
                planSection
                levelSection
                previewSection
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var levelSection: some View {
        switch level {
        case .simple: EmptyView()         // всё уже в базовой секции
        case .mode: patternSection
        case .pro: proSection
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    private var levelPicker: some View {
        Picker("Уровень", selection: $level) {
            ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Секции

    private var medSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Лекарство")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                TextField("Название", text: $medName)
                    .glassField()
                Picker("Единица", selection: $medUnit) {
                    ForEach(DoseUnit.allCases, id: \.self) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                if level == .pro {
                    TextField("Форма (капсула…)", text: $form)
                        .glassField()
                    TextField("Правило приёма (после еды…)", text: $intakeRule)
                        .glassField()
                    HStack {
                        TextField("Цель курса, \(medUnit.title) (опционально)", text: $cumulativeTargetText)
                            .glassField()
                            .keyboardType(.decimalPad)
                        TextField("Вес, кг (опционально)", text: $weightText)
                            .glassField()
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var planSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("План")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                TextField("Название (Блок 1…)", text: $planName)
                    .glassField()
                Toggle("Начать сегодня", isOn: $startsToday)
                if !startsToday {
                    Stepper("Старт: \(startDate.description)", value: $startEpoch, in: dateRange)
                }
                Stepper("Длительность: \(durationDays) дн.", value: $durationDays, in: 1...400)
                if level == .simple {
                    TextField("Доза каждый день, \(medUnit.title)", text: $uniformDoseText)
                        .glassField()
                        .keyboardType(.decimalPad)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var patternSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Режим доз")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Picker("Паттерн", selection: $patternKind) {
                    ForEach(PatternKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch patternKind {
                case .uniform:
                    TextField("Доза каждый день", text: $uniformDoseText)
                        .glassField()
                        .keyboardType(.decimalPad)
                case .alternate:
                    HStack {
                        TextField("Нечётные дни", text: $lowDoseText)
                            .glassField()
                            .keyboardType(.decimalPad)
                        TextField("Чётные дни", text: $highDoseText)
                            .glassField()
                            .keyboardType(.decimalPad)
                    }
                case .segments:
                    TextField("Отрезки 7:24;14:32 (дней:доза)", text: $segmentsText)
                        .glassField()
                        .keyboardType(.numbersAndPunctuation)
                }
                Text("Дни вне отрезков — без приёма. Чередование: нечётный день = первая доза.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var proSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Уведомления")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Toggle("Напоминания", isOn: $notifyOn)
                if notifyOn {
                    Stepper("С \(windowStart):00", value: $windowStart, in: 0...23)
                    Stepper("По \(windowEnd):00", value: $windowEnd, in: 0...23)
                    Picker("Интервал", selection: $windowInterval) {
                        ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) мин").tag($0) }
                    }
                }
                Button {
                    showJSON = true
                } label: {
                    Label("Предпросмотр medplan/1", systemImage: "curlybraces")
                }
                .buttonStyle(GlassButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Предпросмотр сетки

    private var previewSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Предпросмотр сетки")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(doseTotalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let grid = buildGrid()
                if grid.slots.isEmpty {
                    Text("Доз нет")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let entries = grid.slots.sorted { $0.key < $1.key }
                    Text(entries.prefix(60).map { day, slot in
                        "\(day): \(slot.dose == 0 ? "—" : shortDose(slot.dose))"
                    }.joined(separator: "  ·  ") + (entries.count > 60 ? "  ·  …" : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var jsonPreviewSheet: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                ScrollView {
                    Text(previewJSON())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .navigationTitle("medplan/1")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { showJSON = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Логика

    private var doseTotalText: String {
        let grid = buildGrid()
        let total = grid.slots.values.reduce(0.0) { $0 + $1.dose }
        return "Σ \(doseText(total, unit: medUnit)) · \(grid.slots.values.filter { $0.dose > 0 }.count) дн. приёма"
    }

    private func buildGrid() -> DayGrid {
        let pattern: SchedulePattern
        switch level {
        case .simple, .pro:
            pattern = .uniform(dose: parse(uniformDoseText))
        case .mode:
            switch patternKind {
            case .uniform: pattern = .uniform(dose: parse(uniformDoseText))
            case .alternate:
                pattern = .alternate(low: parse(lowDoseText), high: parse(highDoseText))
            case .segments: pattern = .segments(parseSegments())
            }
        }
        return pattern.expand(totalDays: durationDays)
    }

    private func parse(_ text: String) -> Double {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    /// `7:24;14:32` → [(7, 24), (14, 32)].
    private func parseSegments() -> [(days: Int, dose: Double)] {
        segmentsText
            .split(separator: ";")
            .compactMap { part -> (days: Int, dose: Double)? in
                let pair = part.split(separator: ":")
                guard pair.count == 2,
                      let days = Int(pair[0]), days > 0,
                      let dose = Double(pair[1].replacingOccurrences(of: ",", with: "."))
                else { return nil }
                return (days, dose)
            }
    }

    private func previewJSON() -> String {
        let file = buildMedPlanFile()
        guard let data = try? MedPlanCodec.encodeFile(medication: file.0, plan: file.1),
              let json = String(data: data, encoding: .utf8) else { return "—" }
        return json
    }

    /// Сборка сущностей черновика (валидацию делает save()).
    private func buildEntities() -> (Medication, Plan)? {
        let trimmedMedName = medName.trimmingCharacters(in: .whitespaces)
        let trimmedPlanName = (planName.trimmingCharacters(in: .whitespaces))
        guard !trimmedMedName.isEmpty, durationDays > 0 else { return nil }

        let window: NotifyWindow? = (level == .pro && notifyOn)
            ? NotifyWindow(startHour: windowStart, endHour: max(windowEnd, windowStart),
                           intervalMinutes: windowInterval)
            : nil
        let medication = Medication(
            name: trimmedMedName, form: nil, unit: medUnit,
            intakeRule: level == .pro ? proText(intakeRule) : nil,
            cumulativeTarget: level == .pro ? proNumber(cumulativeTargetText) : nil,
            weightKg: level == .pro ? proNumber(weightText) : nil,
            notifyWindow: window)
        let plan = Plan(
            medicationId: medication.id,
            name: trimmedPlanName.isEmpty ? trimmedMedName : trimmedPlanName,
            startDate: startsToday ? CivilDate.today() : startDate,
            durationDays: durationDays,
            schedule: buildGrid())
        return (medication, plan)
    }

    /// (Medication, Plan) для предпросмотра JSON — как medplan/1 без id.
    private func buildMedPlanFile() -> (Medication, Plan) {
        buildEntities() ?? (
            Medication(name: medName.isEmpty ? "?" : medName, unit: medUnit),
            Plan(medicationId: UUID(), name: planName.isEmpty ? "План" : planName,
                 durationDays: durationDays, schedule: buildGrid())
        )
    }

    private func proText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func proNumber(_ text: String) -> Double? {
        let value = parse(text)
        return value > 0 ? value : nil
    }

    private func shortDose(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func save() {
        do {
            guard let (medication, plan) = buildEntities() else {
                errorText = "Заполните название лекарства и длительность"
                return
            }
            try store.insert(medication: medication, plan: plan)
            HapticManager.shared.notifySuccess()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Стиль текстового поля поверх стеклянной карточки (§12: один визуал полей).
extension View {
    func glassField() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}
