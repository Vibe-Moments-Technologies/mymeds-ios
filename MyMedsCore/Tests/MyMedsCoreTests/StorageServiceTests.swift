import XCTest
@testable import MyMedsCore

final class StorageServiceTests: XCTestCase {

    private var dir: URL!
    private var storage: StorageService!
    private let ts = Date(timeIntervalSince1970: 1_700_000_000)  // целые секунды: iso8601 round-trip

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymeds-tests-\(UUID().uuidString)")
        storage = StorageService(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func sampleData(medName: String) -> AppData {
        let med = Medication(name: medName, unit: .mg, createdAt: ts)
        var grid = DayGrid()
        grid[1] = DaySlot(dose: 8)
        let plan = Plan(medicationId: med.id, name: "Блок 1",
                        startDate: CivilDate(year: 2026, month: 5, day: 17),
                        durationDays: 1, schedule: grid,
                        createdAt: ts, updatedAt: ts)
        let intake = Intake(planId: plan.id, day: 1, status: .taken,
                            actualDose: 8, takenAt: ts)
        return AppData(medications: [med], plans: [plan], intakes: [intake], exportedAt: ts)
    }

    func testLoadEmptyReturnsNil() {
        XCTAssertNil(storage.load())
    }

    func testSaveLoadRoundTrip() throws {
        let data = sampleData(medName: "Тестовое")
        try storage.save(data)
        let loaded = try XCTUnwrap(storage.load())
        XCTAssertEqual(loaded.medications, data.medications)
        XCTAssertEqual(loaded.plans, data.plans)
        XCTAssertEqual(loaded.intakes, data.intakes)
        XCTAssertEqual(loaded.format, AppData.backupFormat)
    }

    func testSecondSaveCreatesBackupWithPreviousContent() throws {
        try storage.save(sampleData(medName: "Первое"))
        try storage.save(sampleData(medName: "Второе"))

        XCTAssertEqual(storage.load()?.medications.first?.name, "Второе")

        let bakData = try Data(contentsOf: storage.backupURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bak = try decoder.decode(AppData.self, from: bakData)
        XCTAssertEqual(bak.medications.first?.name, "Первое")
    }

    func testCorruptMainFileFallsBackToBackup() throws {
        try storage.save(sampleData(medName: "Живое"))
        try storage.save(sampleData(medName: "Последнее"))
        try Data("not json at all".utf8).write(to: storage.fileURL)
        // .bak — снимок ПЕРЕД последней перезаписью, то есть «Живое» (§9)
        XCTAssertEqual(storage.load()?.medications.first?.name, "Живое")
    }

    func testSaveRejectsInvalidDataAndWritesNothing() {
        var grid = DayGrid()
        grid[5] = DaySlot(dose: 8)   // день вне 1...3
        let badPlan = Plan(medicationId: UUID(), name: "Плохой", durationDays: 3, schedule: grid)
        XCTAssertThrowsError(try storage.save(AppData(plans: [badPlan]))) { error in
            XCTAssertTrue(error is ValidationError, "ожидалась ValidationError, получено \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.fileURL.path))
    }

    func testSaveRejectsDuplicateIntakes() throws {
        let plan = Plan(medicationId: UUID(), name: "П", startDate: CivilDate(year: 2026, month: 5, day: 1),
                        durationDays: 3)
        let a = Intake(planId: plan.id, day: 1, status: .taken, actualDose: 1, takenAt: ts)
        let b = Intake(planId: plan.id, day: 1, status: .skipped, takenAt: ts)
        XCTAssertThrowsError(try storage.save(AppData(plans: [plan], intakes: [a, b])))
    }

    func testSaveRejectsStatusWithoutTakenAt() {
        let plan = Plan(medicationId: UUID(), name: "П", startDate: CivilDate(year: 2026, month: 5, day: 1),
                        durationDays: 3)
        let bad = Intake(planId: plan.id, day: 1, status: .taken, takenAt: nil)
        XCTAssertThrowsError(try storage.save(AppData(plans: [plan], intakes: [bad])))
    }
}
