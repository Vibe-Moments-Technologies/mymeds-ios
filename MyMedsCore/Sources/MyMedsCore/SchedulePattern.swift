import Foundation

// Развёртка правил конструктора — MED_APP_SPEC.md §5/§12: DSL живёт только в
// авторинге, на диске — развёрнутая сетка по дням.

/// Паттерн уровня «Режим»: чередование `8/16`, отрезки `7:24;14:32`.
public enum SchedulePattern: Equatable, Sendable {
    case uniform(dose: Double)
    case alternate(low: Double, high: Double)
    case segments([(days: Int, dose: Double)])

    /// Развёртка в сетку дней 1...totalDays.
    /// Отрезки короче totalDays → хвост без приёма; длиннее → обрезаются.
    public func expand(totalDays: Int) -> DayGrid {
        var grid = DayGrid()
        guard totalDays > 0 else { return grid }
        switch self {
        case .uniform(let dose):
            for day in 1...totalDays {
                grid[day] = DaySlot(dose: dose)
            }
        case .alternate(let low, let high):
            // Нечётные дни — low, чётные — high (день 1 = low)
            for day in 1...totalDays {
                grid[day] = DaySlot(dose: day % 2 == 1 ? low : high)
            }
        case .segments(let segments):
            var day = 1
            for segment in segments {
                for _ in 0..<max(segment.days, 0) {
                    guard day <= totalDays else { break }
                    grid[day] = DaySlot(dose: segment.dose)
                    day += 1
                }
            }
        }
        return grid
    }
}
