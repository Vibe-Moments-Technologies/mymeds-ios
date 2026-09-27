import XCTest
@testable import MyMedsCore

/// Скользящее окно и бюджет 64 — MED_APP_SPEC.md §8.
final class NotificationPlannerTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1_700_000_000)
    private let today = CivilDate(year: 2026, month: 5, day: 17)

    private func med(window: NotifyWindow?, name: String = "Лекарство") -> Medication {
        Medication(name: name, unit: .mg, notifyWindow: window, createdAt: ts)
    }

    private func plan(medId: UUID, days: Int, dose: Double = 8) -> Plan {
        var grid = DayGrid()
        for d in 1...days { grid[d] = DaySlot(dose: dose) }
        return Plan(medicationId: medId, name: "Блок", startDate: today,
                    durationDays: days, schedule: grid, createdAt: ts, updatedAt: ts)
    }

    private func data(_ meds: [Medication], _ plans: [Plan], _ intakes: [Intake] = [],
                      horizon: Int = 3) -> AppData {
        AppData(medications: meds, plans: plans, intakes: intakes,
                settings: Settings(notifyHorizonDays: horizon), exportedAt: ts)
    }

    /// «Сейчас» = конкретный час локального календаря (детерминированно для теста).
    private func now(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(
            year: today.year, month: today.month, day: today.day,
            hour: hour, minute: minute))!
    }

    func testWindowExpansionAndHorizon() {
        let window = NotifyWindow(startHour: 20, endHour: 23, intervalMinutes: 30)
        let m = med(window: window)
        let p = plan(medId: m.id, days: 10)

        let plan = NotificationPlanner.plan(data: data([m], [p]), today: today, now: now(hour: 8))

        // 7 напоминаний в день (20:00…23:00 шаг 30) × 3 дня горизонта = 21
        XCTAssertEqual(plan.total, 21)
        XCTAssertEqual(plan.perMedication[m.id], 21)
        XCTAssertFalse(plan.trimmed)
        XCTAssertEqual(plan.items.first?.date, today)
        XCTAssertEqual(plan.items.first?.hour, 20)
        XCTAssertEqual(plan.items.first?.minute, 0)
        XCTAssertEqual(plan.items.last?.date, today.adding(days: 2))
    }

    func testPastTimesTodaySkipped() {
        let window = NotifyWindow(startHour: 20, endHour: 23, intervalMinutes: 60)
        let m = med(window: window)
        let p = plan(medId: m.id, days: 10)

        let plan = NotificationPlanner.plan(data: data([m], [p]), today: today, now: now(hour: 21, minute: 30))

        // Сегодня только 22:00 и 23:00; два следующих дня по 4 (20,21,22,23)
        XCTAssertEqual(plan.total, 2 + 8)
        XCTAssertTrue(plan.items.allSatisfy { $0.date != today || $0.hour >= 22 })
    }

    func testMarkedDaysAndWindowlessMedsSkipped() {
        let window = NotifyWindow(startHour: 9, endHour: 9, intervalMinutes: 30)  // 1 в день
        let a = med(window: window, name: "A")
        let b = med(window: nil, name: "B")                                        // без напоминаний
        let pa = plan(medId: a.id, days: 10)
        let pb = plan(medId: b.id, days: 10)
        let intake = Intake(planId: pa.id, day: 1, status: .taken, actualDose: 8, takenAt: ts)

        let plan = NotificationPlanner.plan(data: data([a, b], [pa, pb], [intake]),
                                            today: today, now: now(hour: 7))

        // День 1 отмечен → не планируется; лекарство B без окна → вообще нет
        XCTAssertEqual(plan.total, 2)
        XCTAssertTrue(plan.items.allSatisfy { $0.day >= 2 && $0.medicationId == a.id })
        XCTAssertNil(plan.perMedication[b.id])
    }

    func testOverrideGoesIntoBody() {
        let window = NotifyWindow(startHour: 9, endHour: 9, intervalMinutes: 30)
        let m = med(window: window)
        let p = plan(medId: m.id, days: 5, dose: 8)
        let intake = Intake(planId: p.id, day: 1, doseOverride: 24)  // без статуса

        let plan = NotificationPlanner.plan(data: data([m], [p], [intake]),
                                            today: today, now: now(hour: 7))

        XCTAssertEqual(plan.total, 3)
        XCTAssertTrue(plan.items[0].body.contains("24"), plan.items[0].body)
        XCTAssertTrue(plan.items[1].body.contains("8"))   // день 2 — плановая доза
    }

    func testBudgetFitsLimitByCoarseningIntervalNotDays() {
        // Окно 8:00–23:00 шаг 30 = 31 напоминание в день на лекарство.
        let window = NotifyWindow(startHour: 8, endHour: 23, intervalMinutes: 30)
        var meds: [Medication] = []
        var plans: [Plan] = []
        for i in 0..<3 {   // 3 × 31 × 3 дня = 279 — далеко за 64
            let m = med(window: window, name: "M\(i)")
            meds.append(m)
            plans.append(plan(medId: m.id, days: 10))
        }

        let plan = NotificationPlanner.plan(data: data(meds, plans), today: today, now: now(hour: 6))

        XCTAssertLessThanOrEqual(plan.total, NotificationPlanner.systemLimit)
        XCTAssertTrue(plan.trimmed)
        // Горизонт НЕ урезан: напоминания есть на все 3 дня (§8 — сначала интервал)
        let dates = Set(plan.items.map(\.date))
        XCTAssertEqual(dates, Set((0..<3).map { today.adding(days: $0) }))
    }

    func testHorizonFromSettings() {
        let window = NotifyWindow(startHour: 9, endHour: 9, intervalMinutes: 30)
        let m = med(window: window)
        let p = plan(medId: m.id, days: 30)

        let one = NotificationPlanner.plan(data: data([m], [p], horizon: 1), today: today, now: now(hour: 7))
        XCTAssertEqual(one.total, 1)
        let five = NotificationPlanner.plan(data: data([m], [p], horizon: 5), today: today, now: now(hour: 7))
        XCTAssertEqual(five.total, 5)
    }

    func testDraftPlansNotPlanned() {
        let window = NotifyWindow(startHour: 9, endHour: 9, intervalMinutes: 30)
        let m = med(window: window)
        var draft = plan(medId: m.id, days: 5)
        draft.startDate = nil

        let plan = NotificationPlanner.plan(data: data([m], [draft]), today: today, now: now(hour: 7))
        XCTAssertEqual(plan.total, 0)
    }

    func testEmptyWindowProducesNothing() {
        // endHour < startHour — пустое окно: не падать, не планировать
        let window = NotifyWindow(startHour: 23, endHour: 20, intervalMinutes: 30)
        let m = med(window: window)
        let p = plan(medId: m.id, days: 5)

        let plan = NotificationPlanner.plan(data: data([m], [p]), today: today, now: now(hour: 7))
        XCTAssertEqual(plan.total, 0)
    }
}
