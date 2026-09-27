import XCTest
@testable import MyMedsCore

/// Развёртка паттернов конструктора — MED_APP_SPEC.md §5.
final class SchedulePatternTests: XCTestCase {

    func testUniform() {
        let grid = SchedulePattern.uniform(dose: 16).expand(totalDays: 5)
        XCTAssertEqual(grid.slots.count, 5)
        XCTAssertEqual(grid[3]?.dose, 16)
    }

    func testAlternate() {
        // 8/16: день 1 = 8, день 2 = 16 …
        let grid = SchedulePattern.alternate(low: 8, high: 16).expand(totalDays: 5)
        XCTAssertEqual(grid[1]?.dose, 8)
        XCTAssertEqual(grid[2]?.dose, 16)
        XCTAssertEqual(grid[3]?.dose, 8)
        XCTAssertEqual(grid[4]?.dose, 16)
        XCTAssertEqual(grid[5]?.dose, 8)
    }

    func testSegmentsRule7241432() {
        // Правило вида 7:24;14:32 — 7 дней по 24, затем 14 по 32
        let grid = SchedulePattern.segments([(days: 7, dose: 24), (days: 14, dose: 32)])
            .expand(totalDays: 21)
        XCTAssertEqual(grid[1]?.dose, 24)
        XCTAssertEqual(grid[7]?.dose, 24)
        XCTAssertEqual(grid[8]?.dose, 32)
        XCTAssertEqual(grid[21]?.dose, 32)
        XCTAssertEqual(grid.slots.count, 21)
    }

    func testSegmentsShorterThanDurationLeaveTailEmpty() {
        // Отрезки не покрывают длительность → хвост без приёма
        let grid = SchedulePattern.segments([(days: 3, dose: 8)]).expand(totalDays: 7)
        XCTAssertEqual(grid[3]?.dose, 8)
        XCTAssertNil(grid[4])   // нет слота = день без приёма
        XCTAssertNil(grid[7])
    }

    func testSegmentsLongerThanDurationAreCut() {
        let grid = SchedulePattern.segments([(days: 30, dose: 8)]).expand(totalDays: 10)
        XCTAssertEqual(grid.slots.count, 10)
        XCTAssertNil(grid[11])
    }

    func testZeroDurationProducesEmptyGrid() {
        let grid = SchedulePattern.uniform(dose: 8).expand(totalDays: 0)
        XCTAssertTrue(grid.slots.isEmpty)
    }

    func testZeroDoseSegmentMeansRestDays() {
        // Отрезок с дозой 0 = дни без приёма (уровень 1 «без приёма»)
        let grid = SchedulePattern.segments([(days: 7, dose: 24), (days: 7, dose: 0)])
            .expand(totalDays: 14)
        XCTAssertEqual(grid[1]?.dose, 24)
        XCTAssertEqual(grid[8]?.dose, 0)
        XCTAssertEqual(grid[8]?.times, 1)
    }
}
