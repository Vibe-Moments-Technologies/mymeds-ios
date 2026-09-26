import Foundation

/// Гражданская дата: год/месяц/день, без времени и таймзоны (MED_APP_SPEC.md §3).
/// В JSON — строка "YYYY-MM-DD".
///
/// Арифметика дней — целочисленный алгоритм days_from_civil/civil_from_days
/// (Howard Hinnant), идентичный Python `datetime.date`: таймзона, DST и
/// перелёты на неё не влияют (§13.5). Calendar участвует только в одном —
/// «какое сегодня число» (`CivilDate.today`).
public struct CivilDate: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: - Целочисленная арифметика дней (1:1 с Python date)

    /// Дней от 1970-01-01 (days_from_civil).
    public var daysSinceEpoch: Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                 // [0, 399]
        let mp = month + (month > 2 ? -3 : 9)                   // марто-год, [0, 11]
        let doy = (153 * mp + 2) / 5 + day - 1                  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy         // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// civil_from_days — обратное преобразование.
    public init(daysSinceEpoch days: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                                      // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365 // [0, 399]
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)                // [0, 365]
        let mp = (5 * doy + 2) / 153                                     // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                             // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)                                  // [1, 12]
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    public func adding(days: Int) -> CivilDate {
        CivilDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// Знаковая разница в днях: `start.days(to: on)` == Python `(on - start).days`.
    public func days(to other: CivilDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// Сегодня в текущем календаре пользователя (единственная tz-зависимая операция).
    public static func today(calendar: Calendar = .current) -> CivilDate {
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Реальна ли дата: round-trip через дни совпадает с исходником ("2026-02-30" → false).
    public var isValid: Bool {
        CivilDate(daysSinceEpoch: daysSinceEpoch) == self
    }
}

extension CivilDate: Comparable {
    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        lhs.daysSinceEpoch < rhs.daysSinceEpoch
    }
}

extension CivilDate: CustomStringConvertible {
    /// ISO-8601 "YYYY-MM-DD".
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension CivilDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Ожидается дата YYYY-MM-DD, получено \"\(raw)\"")
        }
        self.init(year: year, month: month, day: day)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
