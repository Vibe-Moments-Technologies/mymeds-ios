import Foundation

// Свёртки метрик — MED_APP_SPEC.md §7 (общий слой). Минимум для разделов,
// календаря и heatmap; полная аналитика (адгереция, streak, оверлеи) — этап 5.

public struct PlanStats: Equatable, Sendable {
    public let taken: Int
    public let skipped: Int
    public let missed: Int
    /// sum(actualDose where taken) в unit лекарства — считается всегда, цель не требуется (§7).
    public let cumulativeDose: Double
    public let elapsedDays: Int
    public let progress: Double   // elapsedDays / durationDays, 0...1

    public static let empty = PlanStats(taken: 0, skipped: 0, missed: 0,
                                        cumulativeDose: 0, elapsedDays: 0, progress: 0)
}

/// Один календарный день для heatmap: доля taken. `fraction == nil` = день без приёма.
public struct DaySummary: Equatable, Sendable {
    public let date: CivilDate
    public let total: Int
    public let taken: Int

    public var fraction: Double? {
        total == 0 ? nil : Double(taken) / Double(total)
    }
}

public enum Stats {
    public static func planStats(plan: Plan, data: AppData, today: CivilDate = .today()) -> PlanStats {
        guard let start = plan.startDate else { return .empty }
        let last = PlanStatus.lastDay(of: plan) ?? start
        var byDay: [Int: Intake] = [:]
        for intake in data.intakes where intake.planId == plan.id {
            byDay[intake.day] = intake
        }

        var taken = 0, skipped = 0, missed = 0
        var cumulative = 0.0
        for day in 1...plan.durationDays {
            let date = start.adding(days: day - 1)
            if date > last { break }                    // stoppedAt отсекает хвост (§5)
            guard let slot = plan.schedule[day], slot.dose > 0 else { continue }
            let intake = byDay[day]
            switch intake?.status {
            case .taken:
                taken += 1
                cumulative += intake?.actualDose ?? intake?.doseOverride ?? slot.dose
            case .skipped:
                skipped += 1
            case nil:
                if date < today { missed += 1 }         // производный missed (§6)
            }
        }

        let elapsed: Int
        if today < start {
            elapsed = 0
        } else {
            let natural = start.days(to: today) + 1
            let cappedByEnd = max(start.days(to: last) + 1, 0)
            elapsed = min(natural, plan.durationDays, cappedByEnd)
        }
        let progress = Double(elapsed) / Double(max(plan.durationDays, 1))
        return PlanStats(taken: taken, skipped: skipped, missed: missed,
                         cumulativeDose: cumulative, elapsedDays: elapsed, progress: progress)
    }

    /// Кумулятивная доза по всем планам лекарства (§7: за план и за лекарство).
    public static func medicationCumulative(medicationId: UUID, data: AppData,
                                            today: CivilDate = .today()) -> Double {
        data.plans
            .filter { $0.medicationId == medicationId }
            .reduce(0.0) { $0 + planStats(plan: $1, data: data, today: today).cumulativeDose }
    }

    public static func medicationCounts(medicationId: UUID, data: AppData,
                                        today: CivilDate = .today()) -> (taken: Int, skipped: Int, missed: Int) {
        var result = (taken: 0, skipped: 0, missed: 0)
        for plan in data.plans where plan.medicationId == medicationId {
            let s = planStats(plan: plan, data: data, today: today)
            result.taken += s.taken
            result.skipped += s.skipped
            result.missed += s.missed
        }
        return result
    }

    /// День-за-днём для календаря/heatmap. Включает будущие дни (total > 0, taken = 0) —
    /// UI сам гасит будущие даты.
    public static func daySummaries(data: AppData, from: CivilDate, to: CivilDate,
                                    today: CivilDate = .today()) -> [DaySummary] {
        var out: [DaySummary] = []
        var date = from
        while date <= to {
            let entries = DayResolver.entries(plans: data.plans, on: date)
            var taken = 0
            for entry in entries {
                let intake = data.intakes.first {
                    $0.planId == entry.planId && $0.day == entry.day
                }
                if StatusResolver.status(intake: intake, on: date, today: today) == .taken {
                    taken += 1
                }
            }
            out.append(DaySummary(date: date, total: entries.count, taken: taken))
            date = date.adding(days: 1)
        }
        return out
    }
}
