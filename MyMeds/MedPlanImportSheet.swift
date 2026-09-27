import SwiftUI
import MyMedsCore
import DesignSystem

/// Предпросмотр импорта medplan/1 (§4: импорт через черновик с явным
/// подтверждением) + выбор старта (§5: «сегодня / завтра / выбрать дату»).
struct MedPlanImportSheet: View {
    let file: MedPlanFile
    let data: Data

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var startChoice: StartChoice = .today
    @State private var customDate = Date()
    @State private var errorText: String?

    enum StartChoice: String, CaseIterable, Identifiable {
        case today = "Старт сегодня"
        case tomorrow = "Завтра"
        case pick = "Выбрать дату"
        case draft = "Пока не начинать"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        previewCard
                        startCard
                        Button {
                            confirmImport()
                        } label: {
                            Label("Импортировать план", systemImage: "square.and.arrow.down")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(GlassButtonStyle(tint: Palette.primary, isProminent: true))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Новый план")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var previewCard: some View {
        GlassCard(tint: Palette.primary.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.medication.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                if let form = file.medication.form {
                    Text(form).font(.subheadline).foregroundStyle(.secondary)
                }
                if let rule = file.medication.intakeRule {
                    Label(rule, systemImage: "fork.knife")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider().opacity(0.3)
                Text(file.plan.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Длительность: \(file.plan.durationDays) дн. · дней с приёмом: \(doseDaysCount)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let start = file.plan.startDate {
                    Text("Старт в файле: \(start.humanText)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let target = file.medication.cumulativeTarget {
                    Text("Кумулятивная цель: \(doseText(target, unit: file.medication.unit))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let window = file.medication.notifyWindow {
                    Text(String(format: "Окно напоминаний: %02d:00–%02d:00 каждые %d мин",
                                window.startHour, window.endHour, window.intervalMinutes))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var startCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Когда начать")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Старт", selection: $startChoice) {
                    ForEach(StartChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if startChoice == .pick {
                    DatePicker("Дата старта", selection: $customDate, displayedComponents: .date)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var doseDaysCount: Int {
        file.plan.schedule.slots.values.filter { $0.dose > 0 }.count
    }

    private func confirmImport() {
        let start: CivilDate?
        switch startChoice {
        case .today:
            start = .today()
        case .tomorrow:
            start = .today().adding(days: 1)
        case .pick:
            let c = Calendar.current.dateComponents([.year, .month, .day], from: customDate)
            start = CivilDate(year: c.year!, month: c.month!, day: c.day!)
        case .draft:
            start = nil
        }
        do {
            try store.importMedPlan(data, startDate: start)
            HapticManager.shared.notifySuccess()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
