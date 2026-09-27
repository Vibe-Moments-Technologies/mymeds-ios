import SwiftUI
import MyMedsCore
import DesignSystem

/// Разделы — список лекарств с сегментом «активные/архив» (§12).
/// Архив = завершённые планы, производно из дат, без отдельного экрана.
struct MedicationsListView: View {
    @Environment(DataStore.self) private var store

    enum Segment: String, CaseIterable, Identifiable {
        case active = "Активные"
        case archive = "Архив"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .active
    @State private var showConstructor = false

    private var today: CivilDate { .today() }

    /// Лекарства с незавершёнными планами (или вообще без планов).
    private var activeMedications: [Medication] {
        store.data.medications.filter { med in
            let plans = store.data.plans.filter { $0.medicationId == med.id }
            return plans.isEmpty
                || plans.contains { PlanStatus.state(of: $0, on: today) != .finished }
        }
    }

    /// Завершённые планы, свежие сверху.
    private var finishedPlans: [Plan] {
        store.data.plans
            .filter { PlanStatus.state(of: $0, on: today) == .finished }
            .sorted { ($0.startDate?.daysSinceEpoch ?? 0) > ($1.startDate?.daysSinceEpoch ?? 0) }
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()
            VStack(spacing: 12) {
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        Button {
                            showConstructor = true
                        } label: {
                            Label("Новый план", systemImage: "plus.circle.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        }
                        .buttonStyle(GlassButtonStyle())
                        if segment == .active {
                            ForEach(activeMedications) { med in
                                NavigationLink {
                                    MedicationDetailView(medication: med)
                                } label: {
                                    MedicationRow(medication: med)
                                }
                                .buttonStyle(.plain)
                            }
                            if activeMedications.isEmpty {
                                emptyText("Нет активных разделов",
                                          hint: "Импортируйте план в настройках")
                            }
                        } else {
                            ForEach(finishedPlans) { plan in
                                NavigationLink {
                                    PlanGridView(plan: plan)
                                } label: {
                                    ArchiveRow(plan: plan)
                                }
                                .buttonStyle(.plain)
                            }
                            if finishedPlans.isEmpty {
                                emptyText("Архив пуст",
                                          hint: "Сюда попадают завершённые планы")
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Разделы")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConstructor) {
            PlanConstructorView()
        }
    }

    private func emptyText(_ title: String, hint: String) -> some View {
        GlassCard {
            VStack(spacing: 8) {
                Text(title).font(.system(.headline, design: .rounded))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }
}

/// Строка активного раздела: лекарство + текущий план + прогресс.
struct MedicationRow: View {
    let medication: Medication
    @Environment(DataStore.self) private var store

    private var today: CivilDate { .today() }

    private var plans: [Plan] {
        store.data.plans.filter { $0.medicationId == medication.id }
    }

    /// Текущий план: активный, иначе ближайший незавершённый.
    private var currentPlan: Plan? {
        plans.first { PlanStatus.state(of: $0, on: today) == .active }
            ?? plans.filter { PlanStatus.state(of: $0, on: today) != .finished }
                .min { ($0.startDate?.daysSinceEpoch ?? Int.max) < ($1.startDate?.daysSinceEpoch ?? Int.max) }
    }

    var body: some View {
        GlassCard(tint: medication.accent.opacity(0.22)) {
            HStack(spacing: 14) {
                Circle()
                    .fill(medication.accent)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    if let plan = currentPlan {
                        let stats = Stats.planStats(plan: plan, data: store.data, today: today)
                        Text(plan.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text("день \(max(stats.elapsedDays, 0)) из \(plan.durationDays)")
                            if stats.progress > 0 {
                                ProgressView(value: stats.progress)
                                    .frame(width: 70)
                                    .tint(medication.accent)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("нет активных планов")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                GlassBadge(
                    label: doseText(
                        Stats.medicationCumulative(medicationId: medication.id, data: store.data, today: today),
                        unit: medication.unit),
                    icon: "sum",
                    color: medication.accent)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Строка архива: завершённый план.
struct ArchiveRow: View {
    let plan: Plan
    @Environment(DataStore.self) private var store

    private var medication: Medication? { store.medication(plan.medicationId) }

    var body: some View {
        let stats = Stats.planStats(plan: plan, data: store.data)
        let med = medication
        let unit = med?.unit ?? .mg
        return GlassCard(tint: med?.accent.opacity(0.12)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(med?.name ?? "?") · \(plan.name)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    if let start = plan.startDate, let last = PlanStatus.lastDay(of: plan) {
                        Text("\(start.description) – \(last.description)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("принято \(stats.taken) · \(doseText(stats.cumulativeDose, unit: unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassBadge(label: "завершён", icon: "checkmark.seal", color: .gray)
            }
        }
    }
}
