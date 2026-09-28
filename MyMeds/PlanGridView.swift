import SwiftUI
import MyMedsCore
import DesignSystem

/// План (§12): дневная сетка, отметки, правка дозы дня (через DayDetailSheet).
struct PlanGridView: View {
    let plan: Plan
    @Environment(DataStore.self) private var store
    @State private var detailItem: DataStore.DayItem?
    @State private var errorText: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var medication: Medication? { store.medication(plan.medicationId) }

    var body: some View {
        ZStack {
            MeshGradientBackground()
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if plan.startDate == nil {
                        Text("План не начат — дата старта появится при активации")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 30)
                    } else {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(1...plan.durationDays, id: \.self) { day in
                                dayCell(day)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailItem) { DayDetailSheet(item: $0) }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                              set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var headerCard: some View {
        let stats = Stats.planStats(plan: plan, data: store.data)
        let state = PlanStatus.state(of: plan, on: .today())
        let unit = medication?.unit ?? .mg
        return GlassCard(tint: medication?.accent.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(plan.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    GlassBadge(label: state.label, icon: state.icon, color: state.color)
                }
                if let start = plan.startDate, let last = PlanStatus.lastDay(of: plan) {
                    Text("\(start.description) – \(last.description)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let stopped = plan.stoppedAt {
                    Text("остановлен \(stopped.description)")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    GlassBadge(label: "\(stats.taken) принято", icon: "checkmark", color: .green)
                    GlassBadge(label: "\(stats.skipped) пропущено", icon: "xmark", color: .orange)
                    GlassBadge(label: "\(stats.missed) без отметки", icon: "exclamationmark", color: .red)
                    Spacer(minLength: 0)
                }
                HStack {
                    Text("прогресс \(stats.elapsedDays)/\(plan.durationDays)")
                    Spacer()
                    Text(doseText(stats.cumulativeDose, unit: unit))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let slot = plan.schedule[day]
        let item = store.item(planId: plan.id, day: day)
        let hasDose = (slot?.dose ?? 0) > 0
        return Button {
            if let item { detailItem = item }
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if hasDose {
                    Circle()
                        .fill(item?.status.color ?? Color.gray.opacity(0.5))
                        .frame(width: 9, height: 9)
                    Text(shortDose(item?.plannedDose ?? slot?.dose ?? 0))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer().frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .liquidGlass(cornerRadius: 10,
                         tint: hasDose ? item?.status.color.opacity(0.12) : nil)
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
    }

    private func shortDose(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
