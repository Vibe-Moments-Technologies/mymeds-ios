import XCTest
@testable import MyMedsCore

/// Контракты medplan/1 (§4) и mymeds-backup/1 (§9).
final class MedPlanCodecTests: XCTestCase {

    /// Пример из MED_APP_SPEC.md §4 — дословно.
    private let specExample = """
    {
      "format": "medplan/1",
      "medication": {
        "name": "Акнекутан",
        "unit": "mg",
        "form": "капсулы 8 мг",
        "intakeRule": "во время ужина, с жирной пищей",
        "cumulativeTarget": 8500,
        "weightKg": 68,
        "notifyWindow": { "startHour": 20, "endHour": 23, "intervalMinutes": 30 }
      },
      "plan": {
        "name": "Блок 1",
        "startDate": "2026-05-17",
        "durationDays": 28,
        "schedule": {
          "1":  { "dose": 8,  "times": 1 },
          "2":  { "dose": 16, "times": 1 },
          "22": { "dose": 16, "times": 1 },
          "28": { "dose": 24, "times": 1 }
        }
      }
    }
    """

    func testSpecExampleDecodesAndMaterializes() throws {
        let file = try MedPlanCodec.decodeFile(Data(specExample.utf8))
        XCTAssertEqual(file.format, MedPlanFile.formatID)

        let (med, plan) = try MedPlanCodec.materialize(file)
        XCTAssertEqual(med.name, "Акнекутан")
        XCTAssertEqual(med.unit, .mg)
        XCTAssertEqual(med.form, "капсулы 8 мг")
        XCTAssertEqual(med.intakeRule, "во время ужина, с жирной пищей")
        XCTAssertEqual(med.cumulativeTarget, 8500)
        XCTAssertEqual(med.weightKg, 68)
        XCTAssertEqual(med.notifyWindow?.startHour, 20)
        XCTAssertEqual(med.notifyWindow?.endHour, 23)
        XCTAssertEqual(med.notifyWindow?.intervalMinutes, 30)

        XCTAssertEqual(plan.name, "Блок 1")
        XCTAssertEqual(plan.startDate, CivilDate(year: 2026, month: 5, day: 17))
        XCTAssertEqual(plan.durationDays, 28)
        XCTAssertEqual(plan.schedule.slots.count, 4)
        XCTAssertEqual(plan.schedule[1], DaySlot(dose: 8, times: 1))
        XCTAssertEqual(plan.schedule[28], DaySlot(dose: 24, times: 1))
        XCTAssertNil(plan.stoppedAt)
        // План привязан к созданному лекарству
        XCTAssertEqual(plan.medicationId, med.id)
    }

    func testUnknownMajorVersionRejected() {
        let json = specExample.replacingOccurrences(of: "medplan/1", with: "medplan/2")
        XCTAssertThrowsError(try MedPlanCodec.decodeFile(Data(json.utf8))) { error in
            guard let e = error as? ValidationError else {
                return XCTFail("ожидалась ValidationError, получено \(error)")
            }
            XCTAssertTrue(e.message.contains("medplan/2"))
        }
    }

    func testUnknownUnitRejected() {
        let json = specExample.replacingOccurrences(of: "\"unit\": \"mg\"", with: "\"unit\": \"spoon\"")
        XCTAssertThrowsError(try MedPlanCodec.decodeFile(Data(json.utf8)))
    }

    func testMaterializeEnforcesInvariants() {
        // durationDays <= 0
        let badDuration = MedPlanFile(
            medication: MedPlanFile.MedPart(name: "X", unit: .mg),
            plan: MedPlanFile.PlanPart(name: "П", durationDays: 0))
        XCTAssertThrowsError(try MedPlanCodec.materialize(badDuration))

        // Ключ сетки вне 1...durationDays
        var grid = DayGrid()
        grid[30] = DaySlot(dose: 8)
        let badGrid = MedPlanFile(
            medication: MedPlanFile.MedPart(name: "X", unit: .mg),
            plan: MedPlanFile.PlanPart(name: "П", durationDays: 28, schedule: grid))
        XCTAssertThrowsError(try MedPlanCodec.materialize(badGrid))
    }

    func testEncodeFileContractShape() throws {
        let file = try MedPlanCodec.decodeFile(Data(specExample.utf8))
        let (med, plan) = try MedPlanCodec.materialize(file)

        let data = try MedPlanCodec.encodeFile(medication: med, plan: plan)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Корень — ровно три ключа контракта
        XCTAssertEqual(root.keys.sorted(), ["format", "medication", "plan"])
        XCTAssertEqual(root["format"] as? String, "medplan/1")

        // В файле нет внутренних идентификаторов и timestamp'ов
        let medJSON = try XCTUnwrap(root["medication"] as? [String: Any])
        XCTAssertNil(medJSON["id"])
        XCTAssertNil(medJSON["createdAt"])
        XCTAssertNil(medJSON["colorHex"])
        let planJSON = try XCTUnwrap(root["plan"] as? [String: Any])
        XCTAssertNil(planJSON["id"])
        XCTAssertNil(planJSON["medicationId"])

        // startDate — гражданская дата строкой, schedule — объектная сетка
        XCTAssertEqual(planJSON["startDate"] as? String, "2026-05-17")
        let sched = try XCTUnwrap(planJSON["schedule"] as? [String: Any])
        XCTAssertEqual(sched.keys.sorted { Int($0)! < Int($1)! }, ["1", "2", "22", "28"])
    }

    func testEncodeDecodeRoundTrip() throws {
        let file = try MedPlanCodec.decodeFile(Data(specExample.utf8))
        let (med, plan) = try MedPlanCodec.materialize(file)

        let redecoded = try MedPlanCodec.decodeFile(try MedPlanCodec.encodeFile(medication: med, plan: plan))
        let (med2, plan2) = try MedPlanCodec.materialize(redecoded)

        XCTAssertEqual(med2.name, med.name)
        XCTAssertEqual(med2.unit, med.unit)
        XCTAssertEqual(med2.cumulativeTarget, med.cumulativeTarget)
        XCTAssertEqual(med2.notifyWindow, med.notifyWindow)
        XCTAssertEqual(plan2.name, plan.name)
        XCTAssertEqual(plan2.startDate, plan.startDate)
        XCTAssertEqual(plan2.schedule, plan.schedule)
    }

    // MARK: - mymeds-backup/1 (§9)

    private func backupJSON(format: String = "mymeds-backup/1", durationDays: Int = 2) -> String {
        """
        {
          "format": "\(format)",
          "version": 1,
          "medications": [
            {"id": "501255d6-799c-474d-bf41-2971c28a31b7", "name": "Тест", "unit": "mg",
             "createdAt": "2026-05-01T10:00:00Z"}
          ],
          "plans": [
            {"id": "601255d6-799c-474d-bf41-2971c28a31b7",
             "medicationId": "501255d6-799c-474d-bf41-2971c28a31b7",
             "name": "Блок 1", "startDate": "2026-05-17", "durationDays": \(durationDays),
             "schedule": {"1": {"dose": 8, "times": 1}},
             "createdAt": "2026-05-01T10:00:00Z", "updatedAt": "2026-05-01T10:00:00Z"}
          ],
          "intakes": [
            {"planId": "601255d6-799c-474d-bf41-2971c28a31b7", "day": 1,
             "status": "taken", "actualDose": 8, "takenAt": "2026-05-17T18:30:00Z"}
          ],
          "settings": {"notifyHorizonDays": 3},
          "exportedAt": "2026-05-18T10:00:00Z"
        }
        """
    }

    func testBackupDecodesAndValidates() throws {
        let data = try MedPlanCodec.decodeBackup(Data(backupJSON().utf8))
        XCTAssertEqual(data.medications.count, 1)
        XCTAssertEqual(data.plans.count, 1)
        // Intake без id — терпимое декодирование генерирует его
        XCTAssertEqual(data.intakes.count, 1)
        XCTAssertEqual(data.intakes[0].status, .taken)
        XCTAssertEqual(data.intakes[0].actualDose, 8)
        XCTAssertEqual(data.settings.notifyHorizonDays, 3)
    }

    func testBackupWrongFormatRejected() {
        XCTAssertThrowsError(try MedPlanCodec.decodeBackup(Data(backupJSON(format: "mymeds-backup/2").utf8))) { error in
            XCTAssertTrue(error is ValidationError, "ожидалась ValidationError, получено \(error)")
        }
    }

    func testBackupInvariantViolationRejected() {
        // durationDays = 0 при живой отметке day=1
        XCTAssertThrowsError(try MedPlanCodec.decodeBackup(Data(backupJSON(durationDays: 0).utf8)))
    }

    func testBackupRoundTripViaStorageEncoder() throws {
        let original = try MedPlanCodec.decodeBackup(Data(backupJSON().utf8))
        let reencoded = try appJSONEncoder.encode(original)
        let decoded = try MedPlanCodec.decodeBackup(reencoded)
        XCTAssertEqual(decoded, original)
    }
}
