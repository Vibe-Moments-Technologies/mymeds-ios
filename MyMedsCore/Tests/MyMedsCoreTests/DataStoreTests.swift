import XCTest
@testable import MyMedsCore

/// Правила отметок и импорта — MED_APP_SPEC.md §3, §6.
final class DataStoreTests: XCTestCase {

    private var dir: URL!
    private var store: DataStore!
    private let ts = Date(timeIntervalSince1970: 1_700_000_000)  // целые секунды для iso8601
    private let start = CivilDate(year: 2026, month: 5, day: 17)

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymeds-store-\(UUID().uuidString)")
        store = DataStore(storage: StorageService(directory: dir))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// Сетка: день 1 → 8 мг, день 2 → 16 мг, день 3 → 0 (день без приёма).
    @discardableResult
    private func seed() throws -> (medId: UUID, planId: UUID) {
        let med = Medication(name: "Тест", unit: .mg, createdAt: ts)
        var grid = DayGrid()
        grid[1] = DaySlot(dose: 8)
        grid[2] = DaySlot(dose: 16)
        grid[3] = DaySlot(dose: 0)
        let plan = Plan(medicationId: med.id, name: "Блок", startDate: start,
                        durationDays: 3, schedule: grid, createdAt: ts, updatedAt: ts)
        let data = AppData(medications: [med], plans: [plan], intakes: [],
                           settings: Settings(), exportedAt: ts)
        try store.importBackup(appJSONEncoder.encode(data))
        return (med.id, plan.id)
    }

    // MARK: - Отметки

    func testMarkInheritsScheduleDose() throws {
        let (_, planId) = try seed()
        try store.mark(planId: planId, day: 1, status: .taken, at: ts)

        let intake = try XCTUnwrap(store.intake(planId: planId, day: 1))
        XCTAssertEqual(intake.status, .taken)
        XCTAssertEqual(intake.takenAt, ts)
        XCTAssertEqual(intake.actualDose, 8)  // из сетки плана (§3)
    }

    func testMarkInheritsOverrideOverSchedule() throws {
        let (_, planId) = try seed()
        try store.setDose(24, planId: planId, day: 2)   // перекрытие ДО отметки
        try store.mark(planId: planId, day: 2, status: .taken, at: ts)

        let intake = try XCTUnwrap(store.intake(planId: planId, day: 2))
        XCTAssertEqual(intake.actualDose, 24)           // doseOverride ?? schedule (§3)
        XCTAssertEqual(intake.doseOverride, 24)
    }

    func testResetKeepsDoseOverride() throws {
        let (_, planId) = try seed()
        try store.setDose(24, planId: planId, day: 2)
        try store.mark(planId: planId, day: 2, status: .taken, at: ts)
        try store.resetMark(planId: planId, day: 2)

        let intake = try XCTUnwrap(store.intake(planId: planId, day: 2))
        XCTAssertNil(intake.status)
        XCTAssertNil(intake.takenAt)
        XCTAssertNil(intake.actualDose)
        XCTAssertEqual(intake.doseOverride, 24)  // правило delete_plan_intake (§3)
    }

    func testSetDoseAfterMarkEditsActualDose() throws {
        let (_, planId) = try seed()
        try store.mark(planId: planId, day: 1, status: .taken, at: ts)
        try store.setDose(12, planId: planId, day: 1)

        let intake = try XCTUnwrap(store.intake(planId: planId, day: 1))
        XCTAssertEqual(intake.status, .taken)     // статус не тронут
        XCTAssertEqual(intake.actualDose, 12)     // правка факта
        XCTAssertNil(intake.doseOverride)
    }

    func testSetDoseNilRestoresSchedule() throws {
        let (_, planId) = try seed()
        try store.setDose(24, planId: planId, day: 1)   // override до отметки
        try store.setDose(nil, planId: planId, day: 1)  // убрать перекрытие
        XCTAssertNil(store.intake(planId: planId, day: 1)?.doseOverride)

        try store.mark(planId: planId, day: 1, status: .taken, at: ts)
        try store.setDose(nil, planId: planId, day: 1)  // после отметки nil → доза из сетки
        XCTAssertEqual(store.intake(planId: planId, day: 1)?.actualDose, 8)
    }

    func testMarkRejectsNegativeAndUnknownDay() throws {
        let (_, planId) = try seed()
        XCTAssertThrowsError(try store.setDose(-1, planId: planId, day: 1))
        XCTAssertThrowsError(try store.mark(planId: planId, day: 99, status: .taken))
    }

    // MARK: - Производные статусы (§6)

    func testMissedIsDerivedNotStored() throws {
        let (_, planId) = try seed()
        let tomorrow = start.adding(days: 1)

        // День 1 в прошлом, отметки нет → missed, но в БД записи НЕТ
        let items = store.items(on: start, today: tomorrow)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].status, .missed)
        XCTAssertTrue(store.data.intakes.isEmpty)

        // Более поздняя отметка перезаписывает missed (§6)
        try store.mark(planId: planId, day: 1, status: .taken, at: ts)
        XCTAssertEqual(store.items(on: start, today: tomorrow)[0].status, .taken)
    }

    func testItemsPendingScheduledAndZeroDose() throws {
        try seed()
        let items = store.items(on: start, today: start)
        XCTAssertEqual(items.map(\.status), [.pending])
        XCTAssertEqual(items[0].plannedDose, 8)

        // День 3 (dose 0) элемента не даёт; день 2 в будущем → scheduled
        let day2 = store.items(on: start.adding(days: 1), today: start)
        XCTAssertEqual(day2.map(\.status), [.scheduled])
        XCTAssertTrue(store.items(on: start.adding(days: 2), today: start).isEmpty)
    }

    // MARK: - Хранение

    func testMarksPersistAcrossInstances() throws {
        let (_, planId) = try seed()
        try store.mark(planId: planId, day: 1, status: .taken, at: ts)

        let reopened = DataStore(storage: StorageService(directory: dir))
        let intake = try XCTUnwrap(reopened.intake(planId: planId, day: 1))
        XCTAssertEqual(intake.status, .taken)
        XCTAssertEqual(intake.actualDose, 8)
    }

    // MARK: - Импорт (§4, §9)

    private let medplanJSON = """
    {
      "format": "medplan/1",
      "medication": { "name": "Акнекутан", "unit": "mg" },
      "plan": {
        "name": "Блок 1",
        "durationDays": 2,
        "schedule": { "1": { "dose": 8, "times": 1 }, "2": { "dose": 16, "times": 1 } }
      }
    }
    """

    func testImportMedPlanAppendsAndLinks() throws {
        let (_, planId) = try seed()
        let (med, plan) = try store.importMedPlan(Data(medplanJSON.utf8), startDate: start)

        XCTAssertEqual(store.data.medications.count, 2)
        XCTAssertEqual(store.data.plans.count, 2)
        XCTAssertEqual(plan.medicationId, med.id)
        XCTAssertEqual(plan.startDate, start)
        XCTAssertNotEqual(plan.id, planId)
    }

    func testImportMedPlanWithoutStartDateStaysDraft() throws {
        try seed()
        let (_, plan) = try store.importMedPlan(Data(medplanJSON.utf8), startDate: nil)
        XCTAssertNil(plan.startDate)
        XCTAssertEqual(store.items(on: start).count, 1)  // черновик на home не появился (§5)
    }

    func testImportBackupReplacesEverything() throws {
        try seed()
        let replacement = AppData(medications: [Medication(name: "Новое", unit: .iu, createdAt: ts)],
                                  exportedAt: ts)
        try store.importBackup(appJSONEncoder.encode(replacement))

        XCTAssertEqual(store.data.medications.count, 1)
        XCTAssertEqual(store.data.medications[0].name, "Новое")
        XCTAssertTrue(store.data.plans.isEmpty)
    }

    func testImportRejectsForeignFormat() throws {
        let bad = Data(#"{"format":"medplan/2","medication":{"name":"X","unit":"mg"},"plan":{"name":"P","durationDays":1,"schedule":{}}}"#.utf8)
        XCTAssertThrowsError(try store.importMedPlan(bad, startDate: nil))
    }
}
