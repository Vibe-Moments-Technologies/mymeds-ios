import Foundation
import Observation

/// Состояние приложения: данные + мутации по правилам MED_APP_SPEC.md (§3, §6).
/// Логика живёт в Core (§12); UI вызывает отсюда. Использовать с main actor.
@Observable
public final class DataStore {
    public private(set) var data: AppData
    private let storage: StorageService

    public init(storage: StorageService = StorageService()) {
        self.storage = storage
        self.data = storage.load() ?? AppData()
    }

    // MARK: - Lookup

    public func medication(_ id: UUID) -> Medication? {
        data.medications.first { $0.id == id }
    }

    public func plan(_ id: UUID) -> Plan? {
        data.plans.first { $0.id == id }
    }

    public func intake(planId: UUID, day: Int) -> Intake? {
        data.intakes.first { $0.planId == planId && $0.day == day }
    }

    /// Элемент дня со всем контекстом для UI (§5: Entry — единица всего).
    public struct DayItem: Identifiable, Hashable {
        public let entry: Entry
        public let medication: Medication
        public let plan: Plan
        public let intake: Intake?
        public let status: IntakeStatus

        public var id: String { "\(entry.planId.uuidString)#\(entry.day)" }

        /// Плановая доза с учётом ручного перекрытия — «принять X».
        public var plannedDose: Double { intake?.doseOverride ?? entry.dose }
    }

    public func items(on date: CivilDate, today: CivilDate = .today()) -> [DayItem] {
        DayResolver.entries(plans: data.plans, on: date).compactMap { entry in
            guard let plan = plan(entry.planId),
                  let medication = medication(plan.medicationId) else { return nil }
            let intake = intake(planId: entry.planId, day: entry.day)
            let status = StatusResolver.status(intake: intake, on: date, today: today)
            return DayItem(entry: entry, medication: medication, plan: plan,
                           intake: intake, status: status)
        }
    }

    public func todaysItems() -> [DayItem] {
        items(on: .today())
    }

    // MARK: - Отметки (§3, §6)

    /// Отметить приём. actualDose наследует `doseOverride ?? schedule[day].dose` (§3).
    public func mark(planId: UUID, day: Int, status: Intake.Status, at moment: Date = Date()) throws {
        guard let plan = plan(planId), let slot = plan.schedule[day] else {
            throw ValidationError("План или день сетки не найден")
        }
        var intake = intake(planId: planId, day: day) ?? Intake(planId: planId, day: day)
        intake.status = status
        intake.takenAt = moment
        intake.actualDose = intake.doseOverride ?? slot.dose
        upsert(intake)
        try persist()
    }

    /// Сброс отметки: обнуляет status/takenAt/actualDose, СОХРАНЯЕТ doseOverride (§3).
    public func resetMark(planId: UUID, day: Int) throws {
        guard var intake = intake(planId: planId, day: day) else { return }
        intake.status = nil
        intake.takenAt = nil
        intake.actualDose = nil
        upsert(intake)
        try persist()
    }

    /// Правка дозы дня. До отметки → doseOverride (правка плановой);
    /// после отметки → actualDose (правка факта, статус не трогается).
    /// nil = убрать перекрытие (вернуться к сетке плана).
    public func setDose(_ dose: Double?, planId: UUID, day: Int) throws {
        guard let plan = plan(planId), let slot = plan.schedule[day] else {
            throw ValidationError("План или день сетки не найден")
        }
        if let dose, dose < 0 {
            throw ValidationError("Доза не может быть отрицательной")
        }
        var intake = intake(planId: planId, day: day) ?? Intake(planId: planId, day: day)
        if intake.status != nil {
            intake.actualDose = dose ?? slot.dose
            intake.doseOverride = nil
        } else {
            intake.doseOverride = dose
        }
        upsert(intake)
        try persist()
    }

    // MARK: - Импорт/экспорт (§4, §9)

    /// Полное восстановление из mymeds-backup/1: замена данных, не слияние.
    public func importBackup(_ jsonData: Data) throws {
        let incoming = try MedPlanCodec.decodeBackup(jsonData)
        data = incoming
        try persist()
    }

    /// Импорт плана из medplan/1 — вызывать ПОСЛЕ предпросмотра черновика (§4).
    /// startDate: «сегодня / завтра / выбрать дату» (§5); nil = черновик без старта.
    @discardableResult
    public func importMedPlan(_ jsonData: Data, startDate: CivilDate?) throws -> (Medication, Plan) {
        let file = try MedPlanCodec.decodeFile(jsonData)
        let (medication, imported) = try MedPlanCodec.materialize(file)
        var plan = imported
        plan.startDate = startDate
        data.medications.append(medication)
        data.plans.append(plan)
        try persist()
        return (medication, plan)
    }

    public func exportBackup() throws -> Data {
        try appJSONEncoder.encode(data)
    }

    // MARK: - Настройки (§8: гибкость на лекарство)

    /// Перечитать с диска: в фоне данные мог изменить другой писатель
    /// (Intent/делегат уведомлений, виджет-сценарии) — UI подхватывает их.
    public func reload() {
        if let loaded = storage.load() {
            data = loaded
        }
    }

    public func setNotifyHorizon(days: Int) throws {
        guard days > 0 else {
            throw ValidationError("Горизонт уведомлений должен быть > 0")
        }
        data.settings.notifyHorizonDays = days
        try persist()
    }

    /// Окно напоминаний на лекарство; nil = выключить уведомления лекарства.
    public func setNotifyWindow(_ window: NotifyWindow?, medicationId: UUID) throws {
        guard let idx = data.medications.firstIndex(where: { $0.id == medicationId }) else {
            throw ValidationError("Лекарство не найдено")
        }
        data.medications[idx].notifyWindow = window
        try persist()
    }

    // MARK: - Внутреннее

    private func upsert(_ intake: Intake) {
        if let idx = data.intakes.firstIndex(where: {
            $0.planId == intake.planId && $0.day == intake.day
        }) {
            data.intakes[idx] = intake
        } else {
            data.intakes.append(intake)
        }
    }

    private func persist() throws {
        data = try storage.save(data)
    }
}
