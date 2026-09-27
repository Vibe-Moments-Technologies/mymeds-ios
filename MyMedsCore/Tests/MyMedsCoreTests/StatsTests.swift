import XCTest
@testable import MyMedsCore

/// Свёртки §7: прогресс, кумулятивная доза (всегда, цель не нужна),
/// производный missed, stoppedAt, summaries для heatmap.
final class StatsTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1_700_000_000)
    private let start = CivilDate(year: 2026, month: 5, day: 17)

    private func makePlan(id: UUID = UUID(), medId: UUID, name: String = "Блок",
                          start: CivilDate?, duration: Int, doses: [Int: Double],
                          stopped: CivilDate? = nil) -> Plan {
        var grid = DayGrid()
        for (d, dose) in doses { grid[d] = DaySlot(dose: dose) }
        return Plan(id: id, medicationId: medId, name: name, startDate: start,
                    durationDays: duration, schedule: grid, stoppedAt: stopped,
                    createdAt: ts, updatedAt: ts)
    }

    private func data(meds: [Medication], plans: [Plan], intakes: [Intake] = []) -> AppData {
        AppData(medications: meds, plans: plans, intakes: intakes, exportedAt: ts)
    }

    func testPlanStatsCountsAndCumulative() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        // 3 дня: 8 / 16 / 0 (без приёма). Старт = today-2 → все 3 дня в диапазоне.
        let plan = makePlan(medId: med.id, start: start.adding(days: -2), duration: 3,
                            doses: [1: 8, 2: 16, 3: 0])
        let d = data(meds: [med], plans: [plan], intakes: [
            Intake(planId: plan.id, day: 1, status: .taken, actualDose: 8, takenAt: ts),
        ])
        let today = start

        let s = Stats.planStats(plan: plan, data: d, today: today)
        XCTAssertEqual(s.taken, 1)
        XCTAssertEqual(s.skipped, 0)
        XCTAssertEqual(s.missed, 1)              // день 2 в прошлом, без отметки → missed
        XCTAssertEqual(s.cumulativeDose, 8)      // день 3 (dose 0) не считается вообще
        XCTAssertEqual(s.elapsedDays, 3)
        XCTAssertEqual(s.progress, 1.0, accuracy: 0.001)
    }

    func testCumulativeUsesActualDoseAndCountsSkippedSeparately() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let plan = makePlan(medId: med.id, start: start.adding(days: -2), duration: 3,
                            doses: [1: 8, 2: 16, 3: 8])
        let d = data(meds: [med], plans: [plan], intakes: [
            Intake(planId: plan.id, day: 1, status: .taken, actualDose: 24, takenAt: ts), // факт ≠ план
            Intake(planId: plan.id, day: 2, status: .skipped, takenAt: ts),
        ])
        let s = Stats.planStats(plan: plan, data: d, today: start)
        XCTAssertEqual(s.taken, 1)
        XCTAssertEqual(s.skipped, 1)
        XCTAssertEqual(s.missed, 0)              // день 3 == today → pending, не missed
        XCTAssertEqual(s.cumulativeDose, 24)     // только taken, фактическая доза
    }

    func testStoppedPlanCutsTail() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let plan = makePlan(medId: med.id, start: start.adding(days: -7), duration: 10,
                            doses: Dictionary(uniqueKeysWithValues: (1...10).map { ($0, 8.0) }),
                            stopped: start.adding(days: -3))   // отработан 5 дней
        let d = data(meds: [med], plans: [plan])

        let s = Stats.planStats(plan: plan, data: d, today: start)
        XCTAssertEqual(s.elapsedDays, 5)
        XCTAssertEqual(s.missed, 5)              // только 5 дней до stoppedAt, хвост отсечён
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
    }

    func testDraftAndFuturePlansAreEmpty() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let draft = makePlan(medId: med.id, start: nil, duration: 3, doses: [1: 8])
        let future = makePlan(medId: med.id, start: start.adding(days: 5), duration: 3,
                              doses: [1: 8, 2: 8, 3: 8])
        let d = data(meds: [med], plans: [draft, future])

        XCTAssertEqual(Stats.planStats(plan: draft, data: d, today: start), .empty)
        let f = Stats.planStats(plan: future, data: d, today: start)
        XCTAssertEqual(f.elapsedDays, 0)
        XCTAssertEqual(f.missed, 0)              // будущее не пропущено
        XCTAssertEqual(f.cumulativeDose, 0)
    }

    func testMedicationCumulativeAcrossPlans() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        let p1 = makePlan(medId: med.id, start: start.adding(days: -10), duration: 2,
                          doses: [1: 8, 2: 16])
        let p2 = makePlan(medId: med.id, start: start.adding(days: -5), duration: 2,
                          doses: [1: 32, 2: 40])
        let other = makePlan(medId: UUID(), start: start.adding(days: -5), duration: 1,
                             doses: [1: 100])   // чужое лекарство — не входит
        let d = data(meds: [med], plans: [p1, p2, other], intakes: [
            Intake(planId: p1.id, day: 1, status: .taken, actualDose: 8, takenAt: ts),
            Intake(planId: p1.id, day: 2, status: .taken, actualDose: 16, takenAt: ts),
            Intake(planId: p2.id, day: 1, status: .taken, actualDose: 32, takenAt: ts),
            Intake(planId: other.id, day: 1, status: .taken, actualDose: 100, takenAt: ts),
        ])

        // Цель НЕ требуется — кумулятивная доза считается всегда (кейс пользователя)
        XCTAssertEqual(Stats.medicationCumulative(medicationId: med.id, data: d, today: start), 56)
        let counts = Stats.medicationCounts(medicationId: med.id, data: d, today: start)
        XCTAssertEqual(counts.taken, 3)
        XCTAssertEqual(counts.skipped, 0)
        XCTAssertEqual(counts.missed, 1)         // p2 день 2 в прошлом без отметки
    }

    func testDaySummariesForHeatmap() {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        // 4 дня: 8 / 16 / 0 / 8
        let plan = makePlan(medId: med.id, start: start, duration: 4,
                            doses: [1: 8, 2: 16, 3: 0, 4: 8])
        let d = data(meds: [med], plans: [plan], intakes: [
            Intake(planId: plan.id, day: 1, status: .taken, actualDose: 8, takenAt: ts),
        ])
        // today = день 2: день 1 прошлый taken, день 2 текущий без отметки
        let summaries = Stats.daySummaries(data: d, from: start, to: start.adding(days: 3),
                                           today: start.adding(days: 1))

        XCTAssertEqual(summaries.count, 4)
        XCTAssertEqual(summaries[0].total, 1)
        XCTAssertEqual(summaries[0].fraction, 1.0)                    // всё принято
        XCTAssertEqual(summaries[1].total, 1)
        XCTAssertEqual(summaries[1].fraction, 0.0)                    // день без отметки
        XCTAssertEqual(summaries[2].total, 0)
        XCTAssertNil(summaries[2].fraction)                           // день без приёма → nil
        XCTAssertEqual(summaries[3].total, 1)                         // будущий день присутствует
        XCTAssertEqual(summaries[3].taken, 0)
    }
}
