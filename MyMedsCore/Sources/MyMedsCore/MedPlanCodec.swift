import Foundation

// JSON-контракты: medplan/1 (MED_APP_SPEC.md §4) и mymeds-backup/1 (§9).
// Правила: format обязателен и версионируется; неизвестная версия → внятная
// ошибка, не тихий дефолт; неизвестная единица → ошибка (закрытый список DoseUnit).

/// Содержимое файла medplan/1: один план одного лекарства.
/// Без идентификаторов — контракт платформенно-нейтрален, id генерируются при импорте.
public struct MedPlanFile: Codable, Sendable {
    public static let formatID = "medplan/1"

    public var format: String
    public var medication: MedPart
    public var plan: PlanPart

    public struct MedPart: Codable, Sendable {
        public var name: String
        public var unit: DoseUnit
        public var form: String?
        public var intakeRule: String?
        public var cumulativeTarget: Double?
        public var weightKg: Double?
        public var notifyWindow: NotifyWindow?

        public init(name: String, unit: DoseUnit, form: String? = nil,
                    intakeRule: String? = nil, cumulativeTarget: Double? = nil,
                    weightKg: Double? = nil, notifyWindow: NotifyWindow? = nil) {
            self.name = name
            self.unit = unit
            self.form = form
            self.intakeRule = intakeRule
            self.cumulativeTarget = cumulativeTarget
            self.weightKg = weightKg
            self.notifyWindow = notifyWindow
        }
    }

    public struct PlanPart: Codable, Sendable {
        public var name: String
        public var startDate: CivilDate?
        public var durationDays: Int
        public var schedule: DayGrid

        public init(name: String, startDate: CivilDate? = nil,
                    durationDays: Int, schedule: DayGrid = DayGrid()) {
            self.name = name
            self.startDate = startDate
            self.durationDays = durationDays
            self.schedule = schedule
        }
    }

    public init(format: String = MedPlanFile.formatID, medication: MedPart, plan: PlanPart) {
        self.format = format
        self.medication = medication
        self.plan = plan
    }
}

public enum MedPlanCodec {
    /// Импорт файла плана: строгая проверка формата.
    public static func decodeFile(_ data: Data) throws -> MedPlanFile {
        let file = try appJSONDecoder.decode(MedPlanFile.self, from: data)
        guard file.format == MedPlanFile.formatID else {
            throw ValidationError(
                "Неподдерживаемый формат плана: «\(file.format)», ожидается «\(MedPlanFile.formatID)»")
        }
        return file
    }

    /// Файл → сущности модели: свежие UUID, план привязан к лекарству,
    /// инварианты §3 проверены. Вызывается после предпросмотра черновика (§4).
    public static func materialize(_ file: MedPlanFile, now: Date = Date()) throws -> (Medication, Plan) {
        let medication = Medication(
            name: file.medication.name,
            form: file.medication.form,
            unit: file.medication.unit,
            intakeRule: file.medication.intakeRule,
            cumulativeTarget: file.medication.cumulativeTarget,
            weightKg: file.medication.weightKg,
            notifyWindow: file.medication.notifyWindow,
            createdAt: now)
        let plan = Plan(
            medicationId: medication.id,
            name: file.plan.name,
            startDate: file.plan.startDate,
            durationDays: file.plan.durationDays,
            schedule: file.plan.schedule,
            createdAt: now, updatedAt: now)
        try plan.validate()
        return (medication, plan)
    }

    /// Экспорт плана с его лекарством в medplan/1 (id и timestamp'ы не вывозятся).
    public static func encodeFile(medication: Medication, plan: Plan) throws -> Data {
        let file = MedPlanFile(
            medication: MedPlanFile.MedPart(
                name: medication.name, unit: medication.unit, form: medication.form,
                intakeRule: medication.intakeRule,
                cumulativeTarget: medication.cumulativeTarget,
                weightKg: medication.weightKg,
                notifyWindow: medication.notifyWindow),
            plan: MedPlanFile.PlanPart(
                name: plan.name, startDate: plan.startDate,
                durationDays: plan.durationDays, schedule: plan.schedule))
        return try appJSONEncoder.encode(file)
    }

    /// Полный бэкап (§9): маркер формата + валидация инвариантов.
    /// Сценарий восстановления «потерял телефон» — замена данных, не слияние.
    public static func decodeBackup(_ data: Data) throws -> AppData {
        let appData = try appJSONDecoder.decode(AppData.self, from: data)
        guard appData.format == AppData.backupFormat else {
            throw ValidationError(
                "Неизвестный формат бэкапа: «\(appData.format)», ожидается «\(AppData.backupFormat)»")
        }
        try appData.validate()
        return appData
    }
}
