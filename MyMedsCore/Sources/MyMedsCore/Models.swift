import Foundation

// Модель данных — MED_APP_SPEC.md §3. Три сущности + производные.

/// Единица дозы — закрытый список контракта medplan/1 (§4).
/// Неизвестная единица в JSON → ошибка декодирования, не молчаливый `mg`.
public enum DoseUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case mg, mcg, iu, tablet, capsule, ml, drop

    public var title: String {
        switch self {
        case .mg: return "мг"
        case .mcg: return "мкг"
        case .iu: return "МЕ"
        case .tablet: return "таблетка"
        case .capsule: return "капсула"
        case .ml: return "мл"
        case .drop: return "капля"
        }
    }
}

public struct Medication: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var form: String?
    public var unit: DoseUnit
    public var intakeRule: String?
    // Необязательные оверлеи: пустые → аналитика их не показывает;
    // кумулятивная принятая доза считается в любом случае (§7).
    public var cumulativeTarget: Double?   // nil = чёткой цели нет
    public var weightKg: Double?
    /// Окно напоминаний — НА лекарство; nil = напоминаний нет (§8).
    public var notifyWindow: NotifyWindow?
    public var colorHex: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, form: String? = nil, unit: DoseUnit,
                intakeRule: String? = nil, cumulativeTarget: Double? = nil,
                weightKg: Double? = nil, notifyWindow: NotifyWindow? = nil,
                colorHex: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.form = form
        self.unit = unit
        self.intakeRule = intakeRule
        self.cumulativeTarget = cumulativeTarget
        self.weightKg = weightKg
        self.notifyWindow = notifyWindow
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

public struct Plan: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var medicationId: UUID
    public var name: String
    /// nil = ещё не начат, на home не появляется (§5).
    public var startDate: CivilDate?
    public var durationDays: Int           // > 0
    public var schedule: DayGrid           // 1...durationDays → что принять
    /// Явная ранняя остановка курса (отменил врач); включительно.
    public var stoppedAt: CivilDate?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), medicationId: UUID, name: String,
                startDate: CivilDate? = nil, durationDays: Int,
                schedule: DayGrid = DayGrid(), stoppedAt: CivilDate? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.medicationId = medicationId
        self.name = name
        self.startDate = startDate
        self.durationDays = durationDays
        self.schedule = schedule
        self.stoppedAt = stoppedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Дневная сетка плана. Обёртка над [Int: DaySlot] ради объектной формы JSON
/// `{"1": {...}}`: штатный Codable для [Int: X] кодирует массив пар и сломал бы
/// контракт medplan/1 (§4). Ключи — только целые строки.
public struct DayGrid: Codable, Hashable, Sendable {
    public var slots: [Int: DaySlot]

    public init(_ slots: [Int: DaySlot] = [:]) {
        self.slots = slots
    }

    public subscript(day: Int) -> DaySlot? {
        get { slots[day] }
        set { slots[day] = newValue }
    }

    private struct DayKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DayKey.self)
        var result: [Int: DaySlot] = [:]
        for key in container.allKeys {
            guard let day = Int(key.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container,
                    debugDescription: "Ключ дня сетки должен быть целым числом")
            }
            result[day] = try container.decode(DaySlot.self, forKey: key)
        }
        slots = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DayKey.self)
        for (day, slot) in slots {
            guard let key = DayKey(stringValue: String(day)) else { continue }
            try container.encode(slot, forKey: key)
        }
    }
}

public struct DaySlot: Codable, Hashable, Sendable {
    /// СУММАРНАЯ доза за день в unit лекарства; 0 = день без приёма (§3).
    public var dose: Double
    /// Приёмов в день — только для отображения; отметка всегда одна на день (§13.2).
    public var times: Int

    public init(dose: Double, times: Int = 1) {
        self.dose = dose
        self.times = times
    }
}

public struct Intake: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var planId: UUID
    public var day: Int                  // 1...durationDays
    /// nil = отметки нет (но доза могла быть перекрыта).
    public var status: Status?
    public var actualDose: Double?
    public var takenAt: Date?
    /// Ручная правка плановой дозы ДО отметки; переживает сброс отметки (§3).
    public var doseOverride: Double?

    public enum Status: String, Codable, Hashable, Sendable {
        case taken, skipped
    }

    public init(id: UUID = UUID(), planId: UUID, day: Int, status: Status? = nil,
                actualDose: Double? = nil, takenAt: Date? = nil, doseOverride: Double? = nil) {
        self.id = id
        self.planId = planId
        self.day = day
        self.status = status
        self.actualDose = actualDose
        self.takenAt = takenAt
        self.doseOverride = doseOverride
    }
}

public struct NotifyWindow: Codable, Hashable, Sendable {
    public var startHour: Int            // 20
    public var endHour: Int              // 23
    public var intervalMinutes: Int      // 30

    public init(startHour: Int, endHour: Int, intervalMinutes: Int) {
        self.startHour = startHour
        self.endHour = endHour
        self.intervalMinutes = intervalMinutes
    }
}

public struct Settings: Codable, Hashable, Sendable {
    /// Горизонт планирования уведомлений в днях (§8). Пока это всё (§9).
    public var notifyHorizonDays: Int

    public init(notifyHorizonDays: Int = 3) {
        self.notifyHorizonDays = notifyHorizonDays
    }
}

/// Корень хранения и формат полного бэкапа `mymeds-backup/1` (§9).
public struct AppData: Codable, Hashable, Sendable {
    public static let backupFormat = "mymeds-backup/1"
    public static let schemaVersion = 1

    public var format: String
    public var version: Int              // схема миграций
    public var medications: [Medication]
    public var plans: [Plan]
    public var intakes: [Intake]
    public var settings: Settings
    public var exportedAt: Date

    public init(format: String = AppData.backupFormat,
                version: Int = AppData.schemaVersion,
                medications: [Medication] = [], plans: [Plan] = [],
                intakes: [Intake] = [], settings: Settings = Settings(),
                exportedAt: Date = Date()) {
        self.format = format
        self.version = version
        self.medications = medications
        self.plans = plans
        self.intakes = intakes
        self.settings = settings
        self.exportedAt = exportedAt
    }
}
