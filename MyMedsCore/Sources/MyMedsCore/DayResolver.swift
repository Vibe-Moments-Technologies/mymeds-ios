import Foundation

// Ядро агрегации — MED_APP_SPEC.md §5–6.

/// Единица всего: строка «Сегодня», клетка календаря, точка heatmap,
/// элемент знаменателя адгереции, уведомление (§5).
public struct Entry: Hashable, Sendable {
    public let planId: UUID
    public let medicationId: UUID
    public let day: Int          // день плана, 1-based
    public let dose: Double      // плановая доза из сетки; override применяется у отметки
    public let on: CivilDate

    public init(planId: UUID, medicationId: UUID, day: Int, dose: Double, on: CivilDate) {
        self.planId = planId
        self.medicationId = medicationId
        self.day = day
        self.dose = dose
        self.on = on
    }
}

public enum DayResolver {
    /// Исполняемое определение семантики: `_akn/day_resolver_reference.py`,
    /// порт 1:1 (сверка — `DayResolverTests.testReferenceSelftest`).
    /// Все элементы приёма, назначенные на гражданскую дату `on`.
    public static func entries(plans: [Plan], on date: CivilDate) -> [Entry] {
        var out: [Entry] = []
        for plan in plans {
            guard let start = plan.startDate else { continue }
            if let stopped = plan.stoppedAt, date > stopped { continue }   // stoppedAt включительно
            let n = start.days(to: date) + 1
            guard n >= 1, n <= plan.durationDays else { continue }
            guard let slot = plan.schedule[n], slot.dose > 0 else { continue }  // день без приёма
            out.append(Entry(planId: plan.id, medicationId: plan.medicationId,
                             day: n, dose: slot.dose, on: date))
        }
        return out
    }
}

/// Состояние плана — вычисляется из дат, не хранится (§5).
public enum PlanState: String, Sendable {
    case draft      // startDate == nil
    case upcoming   // today < startDate
    case active     // startDate <= today <= lastDay
    case finished   // today > lastDay
}

public enum PlanStatus {
    /// lastDay = min(startDate + durationDays - 1, stoppedAt ?? ∞).
    public static func lastDay(of plan: Plan) -> CivilDate? {
        guard let start = plan.startDate else { return nil }
        let natural = start.adding(days: plan.durationDays - 1)
        guard let stopped = plan.stoppedAt else { return natural }
        return min(natural, stopped)
    }

    public static func state(of plan: Plan, on today: CivilDate) -> PlanState {
        guard let start = plan.startDate else { return .draft }
        if today < start { return .upcoming }
        if let last = lastDay(of: plan), today > last { return .finished }
        return .active
    }
}

/// Храним только taken/skipped; missed/pending/scheduled — производные (§6).
public enum IntakeStatus: String, Sendable {
    case taken, skipped, missed, pending, scheduled
}

public enum StatusResolver {
    public static func status(intake: Intake?, on date: CivilDate, today: CivilDate) -> IntakeStatus {
        if let stored = intake?.status {
            switch stored {
            case .taken: return .taken
            case .skipped: return .skipped
            }
        }
        // Записи нет или status == nil (день остаётся редактируемым — §6)
        if date < today { return .missed }
        if date == today { return .pending }
        return .scheduled
    }
}
