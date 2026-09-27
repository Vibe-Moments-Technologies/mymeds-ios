import SwiftUI
import MyMedsCore
import DesignSystem

/// GitHub-heatmap (§7/§12): квадрат на календарный день, интенсивность = доля
/// taken. Один компонент на календарь и аналитику — вторая копия запрещена.
struct HeatmapGrid: View {
    let cells: [CivilDate?]              // nil = пустая клетка выравнивания
    let summaries: [Int: DaySummary]     // ключ — daysSinceEpoch
    let today: CivilDate
    var onSelect: (CivilDate) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// Градации §7: нет приёма / 0 / <⅓ / <⅔ / всё принято. Будущее — нейтрально.
    static func color(for summary: DaySummary?, date: CivilDate, today: CivilDate) -> Color {
        guard let summary, summary.total > 0 else {
            return Color.white.opacity(0.06)
        }
        if date > today {
            return Color.white.opacity(0.12)
        }
        guard let fraction = summary.fraction else {
            return Color.white.opacity(0.06)
        }
        if fraction >= 1 { return Color.green }
        if fraction >= 2.0 / 3.0 { return Color.green.opacity(0.65) }
        if fraction >= 1.0 / 3.0 { return Color.green.opacity(0.4) }
        if fraction > 0 { return Color.orange.opacity(0.55) }
        return Color.red.opacity(0.45)
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells.indices, id: \.self) { idx in
                    if let date = cells[idx] {
                        Button {
                            onSelect(date)
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(HeatmapGrid.color(for: summaries[date.daysSinceEpoch],
                                                        date: date, today: today))
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
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }
}

/// Раскладка месяца: клетки пн→вс с ведущими пустыми + заголовок.
enum MonthLayout {
    /// Клетки месяца (nil — выравнивание до понедельника).
    static func cells(anchor: CivilDate) -> [CivilDate?] {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = anchor.year
        comps.month = anchor.month
        comps.day = 1
        guard let firstDate = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDate) else { return [] }
        // weekday: 1=вс … 7=сб → пн=0
        let offset = (cal.component(.weekday, from: firstDate) + 5) % 7
        var cells: [CivilDate?] = Array(repeating: nil, count: offset)
        for day in range {
            cells.append(CivilDate(year: anchor.year, month: anchor.month, day: day))
        }
        return cells
    }

    static func title(anchor: CivilDate) -> String {
        var comps = DateComponents()
        comps.year = anchor.year
        comps.month = anchor.month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return anchor.description }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    static func shift(anchor: CivilDate, months: Int) -> CivilDate {
        var comps = DateComponents()
        comps.year = anchor.year
        comps.month = anchor.month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps),
              let shifted = Calendar.current.date(byAdding: .month, value: months, to: date) else {
            return anchor
        }
        let parts = Calendar.current.dateComponents([.year, .month], from: shifted)
        return CivilDate(year: parts.year!, month: parts.month!, day: 1)
    }

    /// Сводки дней для набора клеток.
    static func summaries(data: AppData, cells: [CivilDate?], today: CivilDate) -> [Int: DaySummary] {
        let dates = cells.compactMap { $0 }
        guard let first = dates.min(), let last = dates.max(), first <= last else { return [:] }
        let list = Stats.daySummaries(data: data, from: first, to: last, today: today)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.date.daysSinceEpoch, $0) })
    }
}
