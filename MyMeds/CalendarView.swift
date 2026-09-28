import SwiftUI
import MyMedsCore
import DesignSystem

/// Календарь (§12): GitHub-heatmap по дням — общий компонент HeatmapGrid
/// (один на календарь и аналитику, §12).
struct CalendarView: View {
    @Environment(DataStore.self) private var store
    @State private var monthAnchor: CivilDate = {
        let t = CivilDate.today()
        return CivilDate(year: t.year, month: t.month, day: 1)
    }()
    @State private var selectedDay: SelectedDay?

    private var today: CivilDate { .today() }
    private let weekdayLabels = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    struct SelectedDay: Identifiable {
        let date: CivilDate
        var id: Int { date.daysSinceEpoch }
    }

    var body: some View {
        let cells = MonthLayout.cells(anchor: monthAnchor)
        return ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    monthHeader
                    weekdayHeader
                    HeatmapGrid(
                        cells: cells,
                        summaries: MonthLayout.summaries(data: store.data, cells: cells, today: today),
                        today: today
                    ) { date in
                        selectedDay = SelectedDay(date: date)
                    }
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
            .buttonStyle(.glass)
            Spacer()
            Text(MonthLayout.title(anchor: monthAnchor))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").padding(10)
            }
            .buttonStyle(.glass)
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

    private func shiftMonth(_ delta: Int) {
        withAnimation(Motion.press) {
            monthAnchor = MonthLayout.shift(anchor: monthAnchor, months: delta)
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
                AppBackground()
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
