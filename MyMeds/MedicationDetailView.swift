import SwiftUI
import MyMedsCore
import DesignSystem

/// Раздел лекарства (§12): его планы, прогресс, кумулятивная доза
/// (за лекарство и за каждый план), история.
struct MedicationDetailView: View {
    let medication: Medication
    @Environment(DataStore.self) private var store

    private var today: CivilDate { .today() }

    private var plans: [Plan] {
        store.data.plans
            .filter { $0.medicationId == medication.id }
            .sorted {
                ($0.startDate?.daysSinceEpoch ?? Int.max) < ($1.startDate?.daysSinceEpoch ?? Int.max)
            }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    cumulativeCard
                    ForEach(plans) { plan in
                        NavigationLink {
                            PlanGridView(plan: plan)
                        } label: {
                            PlanRow(plan: plan, medication: medication)
                        }
                        .buttonStyle(.plain)
                    }
                    if plans.isEmpty {
                        GlassCard {
                            Text("Планов нет — импортируйте medplan/1 в настройках")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        GlassCard(tint: medication.accent.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Circle().fill(medication.accent).frame(width: 14, height: 14)
                    Text(medication.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                }
                if let form = medication.form {
                    Text(form).font(.subheadline).foregroundStyle(.secondary)
                }
                if let rule = medication.intakeRule {
                    Label(rule, systemImage: "fork.knife")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let w = medication.notifyWindow {
                    Label(String(format: "%02d:00–%02d:00 · каждые %d мин",
                                 w.startHour, w.endHour, w.intervalMinutes),
                          systemImage: "bell")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Кумулятивная доза — всегда, цель опциональна (§7, кейс «нет чёткой цели»).
    private var cumulativeCard: some View {
        let cumulative = Stats.medicationCumulative(medicationId: medication.id,
                                                    data: store.data, today: today)
        let counts = Stats.medicationCounts(medicationId: medication.id,
                                            data: store.data, today: today)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Принято суммарно (все планы)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(doseText(cumulative, unit: medication.unit))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(medication.accent)
                    if let target = medication.cumulativeTarget, target > 0 {
                        Text("· \(Int(cumulative / target * 100))% от цели \(doseText(target, unit: medication.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let weight = medication.weightKg, weight > 0 {
                    Text(String(format: "≈ %.1f мг/кг за курс", cumulative / weight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    GlassBadge(label: "\(counts.taken) принято", icon: "checkmark", color: .green)
                    GlassBadge(label: "\(counts.skipped) пропущено", icon: "xmark", color: .orange)
                    GlassBadge(label: "\(counts.missed) без отметки", icon: "exclamationmark", color: .red)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Строка плана: статус, даты, прогресс, принятая доза этого плана.
struct PlanRow: View {
    let plan: Plan
    let medication: Medication
    @Environment(DataStore.self) private var store

    var body: some View {
        let stats = Stats.planStats(plan: plan, data: store.data)
        let state = PlanStatus.state(of: plan, on: .today())
        return GlassCard(tint: medication.accent.opacity(0.15)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(plan.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    GlassBadge(label: state.label, icon: state.icon, color: state.color)
                }
                if let start = plan.startDate {
                    Text("\(start.description) – \(PlanStatus.lastDay(of: plan)?.description ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("не начат — черновик")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(medication.accent)
                            .frame(width: geo.size.width * stats.progress)
                            .animation(Motion.progress, value: stats.progress)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("день \(stats.elapsedDays) из \(plan.durationDays)")
                    Spacer()
                    Text("\(stats.taken) принято · \(doseText(stats.cumulativeDose, unit: medication.unit))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
