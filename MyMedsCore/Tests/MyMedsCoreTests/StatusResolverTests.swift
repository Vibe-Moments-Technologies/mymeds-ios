import XCTest
@testable import MyMedsCore

/// Таблица статусов — MED_APP_SPEC.md §6.
final class StatusResolverTests: XCTestCase {

    private let today = CivilDate(year: 2026, month: 5, day: 20)
    private let yesterday = CivilDate(year: 2026, month: 5, day: 19)
    private let tomorrow = CivilDate(year: 2026, month: 5, day: 21)

    private func intake(_ status: Intake.Status?) -> Intake {
        Intake(planId: UUID(), day: 1, status: status,
               actualDose: status == .taken ? 8 : nil,
               takenAt: status == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testStoredStatusesWin() {
        XCTAssertEqual(StatusResolver.status(intake: intake(.taken), on: today, today: today), .taken)
        XCTAssertEqual(StatusResolver.status(intake: intake(.skipped), on: today, today: today), .skipped)
        // Хранимый статус важнее даты: отметка прошлого дня остаётся taken
        XCTAssertEqual(StatusResolver.status(intake: intake(.taken), on: yesterday, today: today), .taken)
        XCTAssertEqual(StatusResolver.status(intake: intake(.skipped), on: yesterday, today: today), .skipped)
    }

    func testDerivedStatuses() {
        // Записи нет
        XCTAssertEqual(StatusResolver.status(intake: nil, on: yesterday, today: today), .missed)
        XCTAssertEqual(StatusResolver.status(intake: nil, on: today, today: today), .pending)
        XCTAssertEqual(StatusResolver.status(intake: nil, on: tomorrow, today: today), .scheduled)
        // Запись есть, но status == nil (перекрыта доза) — те же правила
        XCTAssertEqual(StatusResolver.status(intake: intake(nil), on: yesterday, today: today), .missed)
        XCTAssertEqual(StatusResolver.status(intake: intake(nil), on: today, today: today), .pending)
        XCTAssertEqual(StatusResolver.status(intake: intake(nil), on: tomorrow, today: today), .scheduled)
    }

    func testMissedIsNotFinalMark() {
        // §6: missed — не фактическая отметка, день остаётся редактируемым,
        // более поздняя отметка его перезаписывает.
        var i = intake(nil)
        XCTAssertEqual(StatusResolver.status(intake: i, on: yesterday, today: today), .missed)
        i.status = .taken
        i.takenAt = Date(timeIntervalSince1970: 1_700_000_000)
        i.actualDose = 8
        XCTAssertEqual(StatusResolver.status(intake: i, on: yesterday, today: today), .taken)
    }
}
