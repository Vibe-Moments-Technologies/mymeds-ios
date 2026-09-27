import Foundation

// Универсальная аналитика — MED_APP_SPEC.md §7. Два слоя: общий (любое
// лекарство) и оверлей (показывается, только если заполнены поля).

public struct AdherenceStats: Equatable, Sendable {
    public let taken: Int
    public let skipped: Int
    public let missed: Int

    public var total: Int { taken + skipped + missed }

    /// nil — за период нет ни одного решённого дня (нечем считать).
    public var adherence: Double? {
        total == 0 ? nil : Double(taken) / Double(total)
    }
}

public enum Analytics {
    /// Адгереция за период (§7): `taken / (taken + skipped + missed)`.
    /// pending/scheduled в знаменатель не входят — только решённые дни.
    /// `medicationId == nil` → по объединению всех разделов (домашняя аналитика).
    public static func adherence(data: AppData, from: CivilDate, to: CivilDate,
                                 medicationId: UUID? = nil,
                                 today: CivilDate = .today()) -> AdherenceStats {
        var taken = 0, skipped = 0, missed = 0
        var date = from
        while date <= to {
            for entry in entries(data, on: date, medicationId: medicationId) {
                switch StatusResolver.status(intake: intake(data, entry), on: date, today: today) {
                case .taken: taken += 1
                case .skipped: skipped += 1
                case .missed: missed += 1
                case .pending, .scheduled: break
                }
            }
            date = date.adding(days: 1)
        }
        return AdherenceStats(taken: taken, skipped: skipped, missed: missed)
    }

    /// Streak (§7): цепочка дней **с entries**, где все элементы taken.
    /// Дни без entries цепочку не рвут и не считаются. Сегодняшний день,
    /// пока он в прогрессе (только pending), цепочку не рвёт и не считается;
    /// явный skip сегодня — рвёт.
    public static func currentStreak(data: AppData, today: CivilDate = .today()) -> Int {
        var streak = 0
        var date = today
        let floor = data.plans.compactMap(\.startDate).min()
        var guardIterations = 0
        while guardIterations < 5000 {
            guardIterations += 1
            if let floor, date < floor { break }
            let dayEntries = entries(data, on: date, medicationId: nil)
            if dayEntries.isEmpty {
                date = date.adding(days: -1)     // окно между блоками — не разрыв
                continue
            }
            let statuses = dayEntries.map {
                StatusResolver.status(intake: intake(data, $0), on: date, today: today)
            }
            if statuses.allSatisfy({ $0 == .taken }) {
                streak += 1
                date = date.adding(days: -1)
                continue
            }
            if date == today, statuses.allSatisfy({ $0 == .pending || $0 == .taken }) {
                date = date.adding(days: -1)     // день ещё идёт — игнорируем
                continue
            }
            break                                // skipped/missed — разрыв
        }
        return streak
    }

    /// Среднее время отметки (§7): медиана timeOfDay(takenAt), минуты от полуночи.
    public static func medianMarkMinutes(data: AppData, calendar: Calendar = .current) -> Int? {
        let minutes = data.intakes.compactMap { mark -> Int? in
            guard mark.status == .taken, let at = mark.takenAt else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: at)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        let mid = minutes.count / 2
        return minutes.count % 2 == 1 ? minutes[mid] : (minutes[mid - 1] + minutes[mid]) / 2
    }

    /// Оверлей Акнекутана (§7) — считается всегда, UI показывает только непустое.
    public struct Overlay: Equatable, Sendable {
        /// Принято суммарно по всем планам лекарства (всегда, цель не нужна).
        public let cumulativeDose: Double
        /// Средняя доза за день по последним 14 дням (taken).
        public let avgDailyDose14: Double
        /// % от цели — nil без cumulativeTarget.
        public let percentOfTarget: Double?
        /// avg14 / weightKg — nil без weightKg.
        public let mgPerKgDay: Double?
        /// Прогноз: остаток до цели / avg14 — nil без цели или при avg14 == 0.
        public let daysToTarget: Int?
    }

    public static func overlay(medicationId: UUID, data: AppData,
                               today: CivilDate = .today()) -> Overlay {
        let cumulative = Stats.medicationCumulative(medicationId: medicationId,
                                                    data: data, today: today)
        var sum14 = 0.0
        for offset in 0..<14 {
            let date = today.adding(days: -offset)
            for entry in entries(data, on: date, medicationId: medicationId) {
                if let mark = intake(data, entry), mark.status == .taken {
                    sum14 += mark.actualDose ?? entry.dose
                }
            }
        }
        let avg14 = sum14 / 14

        let med = data.medications.first { $0.id == medicationId }
        var percent: Double?
        var days: Int?
        if let target = med?.cumulativeTarget, target > 0 {
            percent = cumulative / target * 100
            if avg14 > 0 {
                days = max(0, Int(ceil((target - cumulative) / avg14)))
            }
        }
        let mgPerKg: Double?
        if let weight = med?.weightKg, weight > 0 {
            mgPerKg = avg14 / weight
        } else {
            mgPerKg = nil
        }
        return Overlay(cumulativeDose: cumulative, avgDailyDose14: avg14,
                       percentOfTarget: percent, mgPerKgDay: mgPerKg, daysToTarget: days)
    }

    // MARK: - Внутреннее

    private static func entries(_ data: AppData, on date: CivilDate, medicationId: UUID?) -> [Entry] {
        let all = DayResolver.entries(plans: data.plans, on: date)
        guard let medicationId else { return all }
        return all.filter { $0.medicationId == medicationId }
    }

    private static func intake(_ data: AppData, _ entry: Entry) -> Intake? {
        data.intakes.first { $0.planId == entry.planId && $0.day == entry.day }
    }
}
