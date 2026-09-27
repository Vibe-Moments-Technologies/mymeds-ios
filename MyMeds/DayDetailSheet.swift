import SwiftUI
import MyMedsCore
import DesignSystem

/// Детали дня: статус, плановая/фактическая доза, правка дозы, отметка и сброс.
struct DayDetailSheet: View {
    let item: DataStore.DayItem

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var doseInput: String = ""
    @State private var errorText: String?

    private var currentIntake: Intake? {
        store.intake(planId: item.entry.planId, day: item.entry.day)
    }

    private var status: IntakeStatus {
        StatusResolver.status(intake: currentIntake, on: item.entry.on, today: .today())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        doseCard
                        actionsCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(item.entry.on.humanText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .onAppear {
            doseInput = formatDose(currentIntake?.actualDose ?? item.plannedDose)
        }
    }

    private var headerCard: some View {
        GlassCard(tint: item.medication.accent.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.medication.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    GlassBadge(label: status.label, icon: status.icon, color: status.color)
                }
                Text("\(item.plan.name) · день \(item.entry.day) из \(item.plan.durationDays)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let form = item.medication.form {
                    Text(form).font(.caption).foregroundStyle(.secondary)
                }
                if let rule = item.medication.intakeRule {
                    Label(rule, systemImage: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let takenAt = currentIntake?.takenAt {
                    Label {
                        Text("отмечено в ") + Text(takenAt, style: .time)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var doseCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Доза")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("план: \(doseText(item.entry.dose, unit: item.medication.unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let override = currentIntake?.doseOverride {
                        Text("вручную: \(doseText(override, unit: item.medication.unit))")
                            .font(.caption)
                            .foregroundStyle(item.medication.accent)
                    }
                    if let actual = currentIntake?.actualDose {
                        Text("факт: \(doseText(actual, unit: item.medication.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    TextField("доза", text: $doseInput)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .liquidGlass(cornerRadius: 12, glow: 0.2)
                    Text(item.medication.unit.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Сохранить") { saveDose() }
                        .buttonStyle(GlassButtonStyle(tint: item.medication.accent, isProminent: true))
                    Button {
                        doseInput = formatDose(item.entry.dose)
                        saveDose(clear: true)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .padding(10)
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                Text(status == .taken || status == .skipped
                     ? "Отметка есть — правка изменит фактическую дозу"
                     : "Отметки нет — правка изменит плановую дозу дня")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsCard: some View {
        HStack(spacing: 12) {
            Button {
                mark(.taken)
            } label: {
                Label("Принял", systemImage: "checkmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GlassButtonStyle(tint: .green, isProminent: true))

            Button {
                mark(.skipped)
            } label: {
                Label("Пропустил", systemImage: "xmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GlassButtonStyle(tint: .orange))

            if currentIntake?.status != nil {
                Button {
                    do {
                        try store.resetMark(planId: item.entry.planId, day: item.entry.day)
                        HapticManager.shared.notifyWarning()
                    } catch {
                        errorText = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .animation(Motion.statusChange, value: status)
    }

    private func mark(_ status: Intake.Status) {
        do {
            try store.mark(planId: item.entry.planId, day: item.entry.day, status: status)
            HapticManager.shared.notifySuccess()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveDose(clear: Bool = false) {
        do {
            if clear {
                try store.setDose(nil, planId: item.entry.planId, day: item.entry.day)
            } else {
                let normalized = doseInput.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized) else {
                    errorText = "Не число: «\(doseInput)»"
                    return
                }
                try store.setDose(value, planId: item.entry.planId, day: item.entry.day)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func formatDose(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
