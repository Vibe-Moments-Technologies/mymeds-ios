import XCTest
@testable import MyMedsCore

/// Универсальная аналитика — MED_APP_SPEC.md §7.
final class AnalyticsTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1_700_000_000)
    private let today = CivilDate(year: 2026, month: 5, day: 17)

    private func makePlan(id: UUID = UUID(), medId: UUID, start: CivilDate?, duration: Int,
                          doses: [Int: Double]) -> Plan {
        var grid = DayGrid()
        for (d, dose) in doses { grid[d] = DaySlot(dose: dose) }
        return Plan(id: id, medicationId: medId, name: "Блок", startDate: start,
                    durationDays: duration, schedule: grid, createdAt: ts, updatedAt: ts)
    }

    private func data(meds: [Medication], plans: [Plan], intakes: [Intake] = []) -> AppData {
        AppData(medications: meds, plans: plans, intakes: intakes, exportedAt: ts)
    }

    private func taken(planId: UUID, day: Int, dose: Double,
                       at time: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Intake {
        Intake(planId: planId, day: day, status: .taken, actualDose: dose, takenAt: time)
    }

    // MARK: - Адгереция

    func testAdherenceCountsOnlyResolvedDays() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        // 4 дня: 1 taken, 2 skipped, 3 без отметки (прошлый → missed), 4 = today (pending)
        let plan = makePlan(medId: med.id, start: today.adding(days: -3), duration: 4,
                            doses: [1: 8, 2: 8, 3: 8, 4: 8])
        let d = data(meds: [med], plans: [plan], intakes: [
            taken(planId: plan.id, day: 1, dose: 8),
            Intake(planId: plan.id, day: 2, status: .skipped, takenAt: ts),
        ])

        let stats = Analytics.adherence(data: d, from: today.adding(days: -3), to: today,
                                        today: today)
        XCTAssertEqual(stats.taken, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.missed, 1)
        XCTAssertEqual(stats.total, 3)                    // pending сегодня не в знаменателе
        XCTAssertEqual(stats.adherence ?? -1, 1.0 / 3.0, accuracy: 0.001)
    }

    func testAdherenceFilterByMedicationAndEmptyPeriod() {
        let m1 = Medication(name: "A", unit: .mg, createdAt: ts)
        let m2 = Medication(name: "B", unit: .capsule, createdAt: ts)
        let p1 = makePlan(medId: m1.id, start: today.adding(days: -1), duration: 2, doses: [1: 8, 2: 8])
        let p2 = makePlan(medId: m2.id, start: today.adding(days: -1), duration: 2, doses: [1: 1, 2: 1])
        let d = data(meds: [m1, m2], plans: [p1, p2], intakes: [
            taken(planId: p1.id, day: 1, dose: 8),
            taken(planId: p2.id, day: 1, dose: 1),
            taken(planId: p2.id, day: 2, dose: 1),
        ])

        let onlyA = Analytics.adherence(data: d, from: today.adding(days: -1), to: today,
                                        medicationId: m1.id, today: today)
        XCTAssertEqual(onlyA.taken, 1)
        XCTAssertEqual(onlyA.total, 1)   // день 2 == today → pending, вне знаменателя

        let all = Analytics.adherence(data: d, from: today.adding(days: -1), to: today, today: today)
        XCTAssertEqual(all.taken, 3)
        XCTAssertEqual(all.total, 3)     // p1 день 2 — pending, не входит
        XCTAssertEqual(all.adherence ?? -1, 1.0, accuracy: 0.001)

        // Пустой период → adherence nil, а не деление на ноль
        let empty = Analytics.adherence(data: d, from: today.adding(days: -100),
                                        to: today.adding(days: -90), today: today)
        XCTAssertEqual(empty.total, 0)
        XCTAssertNil(empty.adherence)
    }

    // MARK: - Streak

    func testStreakInProgressTodayDoesNotBreak() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let plan = makePlan(medId: med.id, start: today.adding(days: -6), duration: 7,
                            doses: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 8.0) }))
        var intakes = (1...6).map { taken(planId: plan.id, day: $0, dose: 8) }
        var d = data(meds: [med], plans: [plan], intakes: intakes)

        // Сегодня (день 7) ещё не отмечен → цепочка 6, сегодня не рвёт
        XCTAssertEqual(Analytics.currentStreak(data: d, today: today), 6)

        // Отметили сегодня → 7
        intakes.append(taken(planId: plan.id, day: 7, dose: 8))
        d = data(meds: [med], plans: [plan], intakes: intakes)
        XCTAssertEqual(Analytics.currentStreak(data: d, today: today), 7)
    }

    func testStreakBrokenBySkip() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let plan = makePlan(medId: med.id, start: today.adding(days: -6), duration: 7,
                            doses: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 8.0) }))
        var intakes = (1...5).map { taken(planId: plan.id, day: $0, dose: 8) }
        intakes.append(Intake(planId: plan.id, day: 6, status: .skipped, takenAt: ts))  // вчера skip
        let d = data(meds: [med], plans: [plan], intakes: intakes)

        XCTAssertEqual(Analytics.currentStreak(data: d, today: today), 0)
    }

    func testStreakIgnoresEmptyEntriesDays() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        // День 3 — без приёма (dose 0): цепочку не рвёт и не считается
        let plan = makePlan(medId: med.id, start: today.adding(days: -4), duration: 5,
                            doses: [1: 8, 2: 8, 3: 0, 4: 8, 5: 8])
        let intakes = [1, 2, 4, 5].map { taken(planId: plan.id, day: $0, dose: 8) }
        let d = data(meds: [med], plans: [plan], intakes: intakes)

        XCTAssertEqual(Analytics.currentStreak(data: d, today: today), 4)
    }

    // MARK: - Среднее время отметки

    func testMedianMarkMinutes() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let plan = makePlan(medId: med.id, start: today.adding(days: -2), duration: 3,
                            doses: [1: 8, 2: 8, 3: 8])
        func at(_ h: Int, _ m: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15,
                                                       hour: h, minute: m))!
        }
        let d = data(meds: [med], plans: [plan], intakes: [
            taken(planId: plan.id, day: 1, dose: 8, at: at(10, 0)),    // 600
            taken(planId: plan.id, day: 2, dose: 8, at: at(12, 30)),   // 750
            taken(planId: plan.id, day: 3, dose: 8, at: at(20, 0)),    // 1200
        ])
        XCTAssertEqual(Analytics.medianMarkMinutes(data: d), 750)

        let d2 = data(meds: [med], plans: [plan], intakes: [
            taken(planId: plan.id, day: 1, dose: 8, at: at(10, 0)),
            taken(planId: plan.id, day: 2, dose: 8, at: at(20, 0)),
        ])
        XCTAssertEqual(Analytics.medianMarkMinutes(data: d2), 900)     // чётное → среднее

        XCTAssertNil(Analytics.medianMarkMinutes(data: data(meds: [med], plans: [plan])))
    }

    // MARK: - Оверлей

    func testOverlayWithTargetAndWeight() {
        var med = Medication(name: "Изотретиноин", unit: .mg, createdAt: ts)
        med.cumulativeTarget = 1000
        med.weightKg = 50
        // 5 дней по 100 мг, все приняты в последних 14 днях
        let plan = makePlan(medId: med.id, start: today.adding(days: -10), duration: 5,
                            doses: Dictionary(uniqueKeysWithValues: (1...5).map { ($0, 100.0) }))
        let intakes = (1...5).map { taken(planId: plan.id, day: $0, dose: 100) }
        let d = data(meds: [med], plans: [plan], intakes: intakes)

        let ov = Analytics.overlay(medicationId: med.id, data: d, today: today)
        XCTAssertEqual(ov.cumulativeDose, 500)
        XCTAssertEqual(ov.avgDailyDose14, 500.0 / 14.0, accuracy: 0.001)
        XCTAssertEqual(ov.percentOfTarget ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(ov.mgPerKgDay ?? -1, (500.0 / 14.0) / 50.0, accuracy: 0.001)
        XCTAssertEqual(ov.daysToTarget, 14)   // (1000-500) / (500/14) = 14
    }

    func testOverlayWorksWithoutTargetAndWeight() {
        // Кейс пользователя: чёткой цели нет — кумулятивная доза всё равно считается
        let med = Medication(name: "Витамин D", unit: .iu, createdAt: ts)
        let plan = makePlan(medId: med.id, start: today.adding(days: -2), duration: 2,
                            doses: [1: 2000, 2: 2000])
        let intakes = (1...2).map { taken(planId: plan.id, day: $0, dose: 2000) }
        let d = data(meds: [med], plans: [plan], intakes: intakes)

        let ov = Analytics.overlay(medicationId: med.id, data: d, today: today)
        XCTAssertEqual(ov.cumulativeDose, 4000)
        XCTAssertNil(ov.percentOfTarget)
        XCTAssertNil(ov.mgPerKgDay)
        XCTAssertNil(ov.daysToTarget)
    }
}
