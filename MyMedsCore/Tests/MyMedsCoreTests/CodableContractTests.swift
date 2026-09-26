import XCTest
@testable import MyMedsCore

/// JSON-контракт — MED_APP_SPEC.md §4: объектная форма сетки, закрытый список
/// единиц, ошибки вместо тихих дефолтов.
final class CodableContractTests: XCTestCase {

    func testDayGridEncodesAsJsonObject() throws {
        var grid = DayGrid()
        grid[1] = DaySlot(dose: 8, times: 1)
        grid[22] = DaySlot(dose: 16, times: 2)

        let data = try JSONEncoder().encode(grid)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json.keys.sorted { Int($0)! < Int($1)! }, ["1", "22"])

        let day22 = try XCTUnwrap(json["22"] as? [String: Any])
        XCTAssertEqual(day22["dose"] as? Double, 16)
        XCTAssertEqual(day22["times"] as? Int, 2)

        XCTAssertEqual(try JSONDecoder().decode(DayGrid.self, from: data), grid)
    }

    func testSpecSection4ScheduleDecodes() throws {
        // Сетка из примера MED_APP_SPEC.md §4 — дословно.
        let json = """
        {
          "1":  { "dose": 8,  "times": 1 },
          "2":  { "dose": 16, "times": 1 },
          "22": { "dose": 16, "times": 1 },
          "28": { "dose": 24, "times": 1 }
        }
        """
        let grid = try JSONDecoder().decode(DayGrid.self, from: Data(json.utf8))
        XCTAssertEqual(grid.slots.count, 4)
        XCTAssertEqual(grid[1]?.dose, 8)
        XCTAssertEqual(grid[2]?.dose, 16)
        XCTAssertEqual(grid[22]?.dose, 16)
        XCTAssertEqual(grid[28]?.dose, 24)
    }

    func testDayGridRejectsNonIntegerKey() {
        let bad = Data(#"{"monday": {"dose": 8, "times": 1}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DayGrid.self, from: bad))
    }

    func testUnknownUnitIsRejected() {
        // §4: неизвестная единица → ошибка импорта, не молчаливый mg.
        let bad = Data(#"{"name":"X","unit":"spoon","createdAt":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Medication.self, from: bad))
    }

    func testKnownUnitsDecode() throws {
        for unit in DoseUnit.allCases {
            let json = #"{"name":"X","unit":"\#(unit.rawValue)","createdAt":0}"#
            let med = try JSONDecoder().decode(Medication.self, from: Data(json.utf8))
            XCTAssertEqual(med.unit, unit)
        }
    }

    func testAppDataRoundTripWithNilOptionals() throws {
        let med = Medication(name: "Витамин D", unit: .iu,
                             cumulativeTarget: nil, weightKg: nil, notifyWindow: nil,
                             createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = AppData(medications: [med], exportedAt: Date(timeIntervalSince1970: 1_700_000_001))

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AppData.self, from: encoded)

        XCTAssertEqual(decoded, data)
        XCTAssertEqual(decoded.format, "mymeds-backup/1")
        XCTAssertNil(decoded.medications[0].notifyWindow)
    }

    func testNotifyWindowRoundTrip() throws {
        let window = NotifyWindow(startHour: 20, endHour: 23, intervalMinutes: 30)
        let med = Medication(name: "Акнекутан", unit: .mg, form: "капсулы 8 мг",
                             intakeRule: "во время ужина, с жирной пищей",
                             cumulativeTarget: 8500, weightKg: 68, notifyWindow: window,
                             createdAt: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(
            Medication.self, from: JSONEncoder().encode(med))
        XCTAssertEqual(decoded.notifyWindow, window)
        XCTAssertEqual(decoded.cumulativeTarget, 8500)
    }
}
