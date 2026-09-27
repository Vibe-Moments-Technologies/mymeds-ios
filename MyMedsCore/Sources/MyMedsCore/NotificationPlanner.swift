import Foundation

// Уведомления — MED_APP_SPEC.md §8. Планировщик — чистая функция (без
// UNUserNotificationCenter), поэтому тестируется где угодно; системный
// адаптер живёт в app-таргете (Notifications.swift).

/// Одно отложенное локальное уведомление.
public struct ScheduledNotification: Equatable, Hashable, Sendable {
    public let id: String
    public let medicationId: UUID
    public let planId: UUID
    public let day: Int
    public let date: CivilDate
    public let hour: Int
    public let minute: Int
    public let title: String
    public let body: String
}

/// Результат планирования + статистика бюджета для настроек («X из 64», §8).
public struct NotificationPlan: Equatable, Sendable {
    public var items: [ScheduledNotification]
    public var perMedication: [UUID: Int]
    /// Бюджет заставил огрубить интервалы или урезать горизонт.
    public var trimmed: Bool
    public var total: Int { items.count }
}

public enum NotificationPlanner {
    /// Жёсткий лимит отложенных локальных уведомлений на приложение (iOS).
    public static let systemLimit = 64

    /// Скользящее окно (§8): ближайшие `horizonDays` дней, только неотмеченные
    /// entries, только лекарства с `notifyWindow`. Идемпотентно: вызывающий
    /// отменяет все pending и ставит этот список целиком.
    ///
    /// Бюджет: при переполнении 64 сначала укрупняется интервал самого
    /// «прожорливого» лекарства (×2, «сокращать интервал окна, а не число
    /// дней» — §8), и только когда все интервалы на пределе — режется горизонт.
    public static func plan(
        data: AppData,
        today: CivilDate = .today(),
        now: Date = Date(),
        horizonDays: Int? = nil,
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let requestedHorizon = max(1, horizonDays ?? data.settings.notifyHorizonDays)
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (nowParts.hour ?? 0) * 60 + (nowParts.minute ?? 0)

        var effectiveHorizon = requestedHorizon
        var intervals: [UUID: Int] = [:]   // medId → эффективный интервал, мин
        var result = build(data: data, today: today, horizon: effectiveHorizon,
                           skipBeforeMinutes: nowMinutes, intervals: intervals)
        var trimmed = false

        while result.total > systemLimit {
            // Кандидаты на огрубление: лекарства, чей интервал ещё можно удвоить.
            let candidate = result.perMedication
                .filter { medId, count in
                    count > 0 && (intervals[medId] ?? baseInterval(data, medId) ?? 60) < 1440
                }
                .max { $0.value < $1.value }
            if let (medId, _) = candidate {
                let current = intervals[medId] ?? baseInterval(data, medId) ?? 60
                intervals[medId] = min(current * 2, 1440)
                trimmed = true
            } else if effectiveHorizon > 1 {
                effectiveHorizon -= 1
                trimmed = true
            } else {
                break
            }
            result = build(data: data, today: today, horizon: effectiveHorizon,
                           skipBeforeMinutes: nowMinutes, intervals: intervals)
        }
        result.trimmed = trimmed || result.total > systemLimit
        return result
    }

    // MARK: - Внутреннее

    private static func baseInterval(_ data: AppData, _ medId: UUID) -> Int? {
        data.medications.first { $0.id == medId }?.notifyWindow?.intervalMinutes
    }

    private static func build(
        data: AppData,
        today: CivilDate,
        horizon: Int,
        skipBeforeMinutes: Int,
        intervals: [UUID: Int]
    ) -> NotificationPlan {
        var items: [ScheduledNotification] = []
        var perMed: [UUID: Int] = [:]

        for dayOffset in 0..<horizon {
            let date = today.adding(days: dayOffset)
            for entry in DayResolver.entries(plans: data.plans, on: date) {
                let intake = data.intakes.first {
                    $0.planId == entry.planId && $0.day == entry.day
                }
                // Отмеченные дни (taken/skipped) не напоминаем (§6)
                if intake?.status != nil { continue }
                guard let med = data.medications.first(where: { $0.id == entry.medicationId }),
                      let window = med.notifyWindow else { continue }

                let interval = max(1, intervals[med.id] ?? window.intervalMinutes)
                let dose = intake?.doseOverride ?? entry.dose
                let planName = data.plans.first { $0.id == entry.planId }?.name ?? ""
                let body = "Принять: \(doseText(dose, unit: med.unit)) · \(planName), день \(entry.day)"

                var minute = window.startHour * 60
                let endMinute = window.endHour * 60
                while minute <= endMinute {
                    // Сегодняшние напоминания в прошлом не ставим
                    if dayOffset == 0 && minute <= skipBeforeMinutes {
                        minute += interval
                        continue
                    }
                    items.append(ScheduledNotification(
                        id: "rem-\(entry.planId.uuidString)-\(entry.day)-\(minute / 60)-\(minute % 60)",
                        medicationId: med.id,
                        planId: entry.planId,
                        day: entry.day,
                        date: date,
                        hour: minute / 60,
                        minute: minute % 60,
                        title: med.name,
                        body: body))
                    perMed[med.id, default: 0] += 1
                    minute += interval
                }
            }
        }
        items.sort { ($0.date, $0.hour, $0.minute) < ($1.date, $1.hour, $1.minute) }
        return NotificationPlan(items: items, perMedication: perMed, trimmed: false)
    }
}
