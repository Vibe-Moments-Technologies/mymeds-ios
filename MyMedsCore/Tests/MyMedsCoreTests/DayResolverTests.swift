import XCTest
@testable import MyMedsCore

/// Порт 1:1 эталона `_akn/day_resolver_reference.py::_selftest`
/// (MED_APP_SPEC.md §5, §13.1 — первый тест проекта).
/// Если Swift-порт и эталон разойдутся — расхождение найдёт этот тест, а не пользователь.
final class DayResolverTests: XCTestCase {

    private let aknId = UUID()      // p1
    private let vitdId = UUID()     // p2
    private let stoppedId = UUID()  // p3
    private let draftId = UUID()    // p4
    private let gapId = UUID()      // p5

    private func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate {
        CivilDate(year: y, month: m, day: day)
    }

    private func makePlan(id: UUID, start: CivilDate?, duration: Int,
                          doses: [Int: Double], stopped: CivilDate? = nil) -> Plan {
        var grid = DayGrid()
        for (day, dose) in doses { grid[day] = DaySlot(dose: dose) }
        return Plan(id: id, medicationId: UUID(), name: "plan-\(id.uuidString.prefix(4))",
                    startDate: start, durationDays: duration, schedule: grid, stoppedAt: stopped)
    }

    /// Фикстуры — те же пять планов, что в эталонном _selftest.
    private func fixtures() -> [Plan] {
        let akn = makePlan(id: aknId, start: d(2026, 5, 17), duration: 28,
                           doses: Dictionary(uniqueKeysWithValues: (1...28).map { ($0, $0 % 2 == 1 ? 8.0 : 16.0) }))
        let vitd = makePlan(id: vitdId, start: d(2026, 6, 1), duration: 90,
                            doses: Dictionary(uniqueKeysWithValues: (1...90).map { ($0, 2000.0) }))
        let stopped = makePlan(id: stoppedId, start: d(2026, 5, 1), duration: 30,
                               doses: Dictionary(uniqueKeysWithValues: (1...30).map { ($0, 1.0) }),
                               stopped: d(2026, 5, 10))
        let draft = makePlan(id: draftId, start: nil, duration: 10,
                             doses: Dictionary(uniqueKeysWithValues: (1...10).map { ($0, 1.0) }))
        var gapDoses = Dictionary(uniqueKeysWithValues: (1...10).map { ($0, 5.0) })
        gapDoses[2] = 0
        let gap = makePlan(id: gapId, start: d(2026, 5, 1), duration: 10, doses: gapDoses)
        return [akn, vitd, stopped, draft, gap]
    }

    private func ids(_ entries: [Entry]) -> Set<UUID> {
        Set(entries.map(\.planId))
    }

    private func keys(_ entries: [Entry]) -> Set<String> {
        Set(entries.map { "\($0.planId.uuidString)#\($0.day)" })
    }

    func testReferenceSelftest() {
        let ps = fixtures()
        let akn = ps[0]
        let gap = ps[4]

        // 1. Разные даты старта склеиваются по календарной дате, а не по day_num.
        let got = keys(DayResolver.entries(plans: ps, on: d(2026, 6, 1)))
        XCTAssertEqual(got, ["\(aknId.uuidString)#16", "\(vitdId.uuidString)#1"])

        // 2. До старта второго плана в агрегации только первый.
        let day = DayResolver.entries(plans: ps, on: d(2026, 5, 31))
        XCTAssertEqual(ids(day), [aknId])
        XCTAssertEqual(Set(day.map(\.day)), [15])

        // 3. Черновой план не появляется никогда.
        for date in [d(2026, 5, 5), d(2026, 6, 1), d(2026, 12, 1)] {
            XCTAssertFalse(ids(DayResolver.entries(plans: ps, on: date)).contains(draftId), "\(date)")
        }

        // 4. Остановленный план даёт элементы только до stoppedAt включительно.
        XCTAssertEqual(ids(DayResolver.entries(plans: ps, on: d(2026, 5, 10))), [stoppedId, gapId])
        XCTAssertEqual(ids(DayResolver.entries(plans: ps, on: d(2026, 5, 11))), [])
        XCTAssertEqual(ids(DayResolver.entries(plans: ps, on: d(2026, 5, 20))), [aknId])

        // 5. День с нулевой дозой элемента не даёт; соседние дни дают.
        XCTAssertEqual(DayResolver.entries(plans: [gap], on: d(2026, 5, 2)), [])
        XCTAssertEqual(DayResolver.entries(plans: [gap], on: d(2026, 5, 1)).map(\.dose), [5])
        XCTAssertEqual(DayResolver.entries(plans: [gap], on: d(2026, 5, 3)).map(\.dose), [5])

        // 6. Границы диапазона плана.
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 5, 17)).map(\.day), [1])
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 6, 13)).map(\.day), [28])
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 5, 16)), [])
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 6, 14)), [])

        // 7. После завершения всех планов — пусто.
        XCTAssertEqual(DayResolver.entries(plans: ps, on: d(2026, 12, 1)), [])

        // 8. Доза берётся из сетки дня, а не из дефолта.
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 5, 17)).map(\.dose), [8])
        XCTAssertEqual(DayResolver.entries(plans: [akn], on: d(2026, 5, 18)).map(\.dose), [16])
    }

    // Дополнительно к эталону: производное состояние плана (§5).

    func testPlanStateIsDerived() {
        let plan = makePlan(id: UUID(), start: d(2026, 5, 1), duration: 10,
                            doses: Dictionary(uniqueKeysWithValues: (1...10).map { ($0, 1.0) }))
        XCTAssertEqual(PlanStatus.state(of: makePlan(id: UUID(), start: nil, duration: 3, doses: [:]),
                                        on: d(2026, 5, 1)), .draft)
        XCTAssertEqual(PlanStatus.state(of: plan, on: d(2026, 4, 30)), .upcoming)
        XCTAssertEqual(PlanStatus.state(of: plan, on: d(2026, 5, 1)), .active)
        XCTAssertEqual(PlanStatus.state(of: plan, on: d(2026, 5, 10)), .active)
        XCTAssertEqual(PlanStatus.state(of: plan, on: d(2026, 5, 11)), .finished)

        let stopped = makePlan(id: UUID(), start: d(2026, 5, 1), duration: 30,
                               doses: [:], stopped: d(2026, 5, 10))
        XCTAssertEqual(PlanStatus.state(of: stopped, on: d(2026, 5, 10)), .active)   // включительно
        XCTAssertEqual(PlanStatus.state(of: stopped, on: d(2026, 5, 11)), .finished)
        XCTAssertEqual(PlanStatus.lastDay(of: stopped), d(2026, 5, 10))
        XCTAssertEqual(PlanStatus.lastDay(of: plan), d(2026, 5, 10))
        XCTAssertNil(PlanStatus.lastDay(of: makePlan(id: UUID(), start: nil, duration: 3, doses: [:])))
    }
}
