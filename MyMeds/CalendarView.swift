import SwiftUI
import MyMedsCore
import DesignSystem

/// Календарь (§12): GitHub-heatmap по дням — квадрат на календарный день,
/// интенсивность = доля taken (градации §7: нет приёма / 0 / <⅓ / <⅔ / всё).
struct CalendarView: View {
    @Environment(DataStore.self) private var store
    @State private var monthAnchor: CivilDate = {
        let t = CivilDate.today()
        return CivilDate(year: t.year, month: t.month, day: 1)
    }()
    @State private var selectedDay: SelectedDay?
    @State private var errorText: String?

    private var today: CivilDate { .today() }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    struct SelectedDay: Identifiable {
        let date: CivilDate
        var id: Int { date.daysSinceEpoch }
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()
            ScrollView {
                VStack(spacing: 14) {
                    monthHeader
                    weekdayHeader
                    heatmap
                    legend
                }
                .padding(16)
            }
        }
        .navigationTitle("Календарь")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { day in
            CalendarDaySheet(date: day.date)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").padding(10)
            }
            .buttonStyle(GlassButtonStyle())
            Spacer()
            Text(monthTitle)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").padding(10)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthDays: [CivilDate?] {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = monthAnchor.year
        comps.month = monthAnchor.month
        comps.day = 1
        guard let firstDate = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDate) else { return [] }
        // Сдвиг до понедельника: weekday 1=вс … 7=сб → пн=0
        let weekday = cal.component(.weekday, from: firstDate)
        let offset = (weekday + 5) % 7
        var cells: [CivilDate?] = Array(repeating: nil, count: offset)
        for day in range {
            cells.append(CivilDate(year: monthAnchor.year, month: monthAnchor.month, day: day))
        }
        return cells
    }

    private var summaries: [Int: DaySummary] {
        guard let lastDay = monthDays.compactMap({ $0 }).last else { return [:] }
        let list = Stats.daySummaries(data: store.data, from: monthAnchor, to: lastDay, today: today)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.date.daysSinceEpoch, $0) })
    }

    private var heatmap: some View {
        let lookup = summaries
        let days = monthDays
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days.indices, id: \.self) { idx in
                if let date = days[idx] {
                    let summary = lookup[date.daysSinceEpoch]
                    Button {
                        selectedDay = SelectedDay(date: date)
                    } label: {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color(for: summary, date: date))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if date == today {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func color(for summary: DaySummary?, date: CivilDate) -> Color {
        guard let summary, summary.total > 0 else {
            return Color.white.opacity(0.06)          // нет приёма
        }
        if date > today {
            return Color.white.opacity(0.12)          // будущее — нейтрально
        }
        guard let fraction = summary.fraction else {
            return Color.white.opacity(0.06)
        }
        if fraction >= 1 { return Color.green }
        if fraction >= 2.0 / 3.0 { return Color.green.opacity(0.65) }
        if fraction >= 1.0 / 3.0 { return Color.green.opacity(0.4) }
        if fraction > 0 { return Color.orange.opacity(0.55) }
        return Color.red.opacity(0.45)                // 0 принято
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(Color.white.opacity(0.06), "нет")
            legendItem(Color.red.opacity(0.45), "0")
            legendItem(Color.green.opacity(0.4), "<⅓")
            legendItem(Color.green.opacity(0.65), "<⅔")
            legendItem(Color.green, "всё")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }

    private var monthTitle: String {
        var comps = DateComponents()
        comps.year = monthAnchor.year
        comps.month = monthAnchor.month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthAnchor.description }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func shiftMonth(_ delta: Int) {
        var comps = DateComponents()
        comps.year = monthAnchor.year
        comps.month = monthAnchor.month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps),
              let shifted = Calendar.current.date(byAdding: .month, value: delta, to: date) else { return }
        let parts = Calendar.current.dateComponents([.year, .month], from: shifted)
        withAnimation(Motion.press) {
            monthAnchor = CivilDate(year: parts.year!, month: parts.month!, day: 1)
        }
    }
}

/// Приёмы выбранного дня — те же строки, что на Home (один компонент, §12).
struct CalendarDaySheet: View {
    let date: CivilDate
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detailItem: DataStore.DayItem?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        let items = store.items(on: date)
                        if items.isEmpty {
                            Text("В этот день приёмов нет")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(40)
                        } else {
                            ForEach(items) { item in
                                IntakeRow(item: item,
                                          onDetail: { detailItem = item },
                                          onError: { errorText = $0 })
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(date.humanText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $detailItem) { DayDetailSheet(item: $0) }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }
}
