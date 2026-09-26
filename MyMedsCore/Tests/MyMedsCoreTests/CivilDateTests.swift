import XCTest
@testable import MyMedsCore

/// CivilDate обязан совпадать с Python `datetime.date` — эталон резолва (§5)
/// написан на нём. Якоря ниже вычислены в CPython: `(date(y,m,d) - date(1970,1,1)).days`.
final class CivilDateTests: XCTestCase {

    func testEpochAnchors() {
        XCTAssertEqual(CivilDate(year: 1970, month: 1, day: 1).daysSinceEpoch, 0)
        XCTAssertEqual(CivilDate(year: 2000, month: 1, day: 1).daysSinceEpoch, 10957)
        XCTAssertEqual(CivilDate(year: 2024, month: 2, day: 29).daysSinceEpoch, 19782)
        XCTAssertEqual(CivilDate(year: 2026, month: 5, day: 17).daysSinceEpoch, 20590)
        // До эпохи — отрицательные (алгоритм поддерживает)
        XCTAssertEqual(CivilDate(year: 1969, month: 12, day: 31).daysSinceEpoch, -1)
    }

    func testDaysToMatchesPythonSubtraction() {
        let start = CivilDate(year: 2026, month: 5, day: 17)
        XCTAssertEqual(start.days(to: CivilDate(year: 2026, month: 6, day: 13)), 27)  // день плана 28
        XCTAssertEqual(start.days(to: start), 0)
        XCTAssertEqual(start.days(to: CivilDate(year: 2026, month: 5, day: 16)), -1)
        // Через високосный день
        XCTAssertEqual(CivilDate(year: 2024, month: 2, day: 28).days(to: CivilDate(year: 2024, month: 3, day: 1)), 2)
        // Через год
        XCTAssertEqual(CivilDate(year: 2026, month: 1, day: 1).days(to: CivilDate(year: 2027, month: 1, day: 1)), 365)
    }

    func testRoundTripDaysSinceEpoch() {
        for days in stride(from: -20_000, through: 60_000, by: 97) {
            let date = CivilDate(daysSinceEpoch: days)
            XCTAssertEqual(date.daysSinceEpoch, days, "сбой round-trip для дней \(days) → \(date)")
        }
    }

    func testRoundTripCivilComponents() {
        var date = CivilDate(year: 1999, month: 12, day: 31)
        for _ in 0..<1000 {
            XCTAssertEqual(CivilDate(daysSinceEpoch: date.daysSinceEpoch), date)
            date = date.adding(days: 7)
        }
    }

    func testAddingDays() {
        XCTAssertEqual(CivilDate(year: 2026, month: 12, day: 31).adding(days: 1),
                       CivilDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(CivilDate(year: 2024, month: 2, day: 28).adding(days: 1),
                       CivilDate(year: 2024, month: 2, day: 29))
        XCTAssertEqual(CivilDate(year: 2023, month: 2, day: 28).adding(days: 1),
                       CivilDate(year: 2023, month: 3, day: 1))
        XCTAssertEqual(CivilDate(year: 2026, month: 5, day: 17).adding(days: -1),
                       CivilDate(year: 2026, month: 5, day: 16))
    }

    func testIsValid() {
        XCTAssertTrue(CivilDate(year: 2024, month: 2, day: 29).isValid)
        XCTAssertFalse(CivilDate(year: 2023, month: 2, day: 29).isValid)
        XCTAssertFalse(CivilDate(year: 2026, month: 13, day: 1).isValid)
        XCTAssertFalse(CivilDate(year: 2026, month: 4, day: 31).isValid)
    }

    func testCodableContract() throws {
        let date = CivilDate(year: 2026, month: 5, day: 17)
        let data = try JSONEncoder().encode(date)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-05-17\"")
        XCTAssertEqual(try JSONDecoder().decode(CivilDate.self, from: data), date)

        // Мусор → ошибка, не тихий дефолт (§4)
        for bad in ["\"17.05.2026\"", "\"2026-05\"", "\"\"", "\"a-b-c\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(CivilDate.self, from: Data(bad.utf8)), bad)
        }
    }

    func testComparableAndDescription() {
        XCTAssertLessThan(CivilDate(year: 2026, month: 5, day: 17), CivilDate(year: 2026, month: 5, day: 18))
        XCTAssertLessThan(CivilDate(year: 2025, month: 12, day: 31), CivilDate(year: 2026, month: 1, day: 1))
        XCTAssertEqual(CivilDate(year: 2026, month: 1, day: 5).description, "2026-01-05")
    }

    func testTodayIsValid() {
        XCTAssertTrue(CivilDate.today().isValid)
    }
}
