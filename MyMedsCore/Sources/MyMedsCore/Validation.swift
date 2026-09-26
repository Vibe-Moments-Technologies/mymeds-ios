import Foundation

// Инварианты — MED_APP_SPEC.md §3: проверять при импорте и при сохранении.

public struct ValidationError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

extension Plan {
    public func validate() throws {
        guard durationDays > 0 else {
            throw ValidationError("План «\(name)»: durationDays должен быть > 0")
        }
        if let start = startDate {
            guard start.isValid else {
                throw ValidationError("План «\(name)»: нереальная дата старта \(start)")
            }
            if let stopped = stoppedAt {
                guard stopped.isValid, stopped >= start else {
                    throw ValidationError("План «\(name)»: stoppedAt раньше/нереальнее startDate")
                }
            }
        }
        for (day, slot) in schedule.slots {
            guard (1...durationDays).contains(day) else {
                throw ValidationError("План «\(name)»: день \(day) вне 1...\(durationDays)")
            }
            guard slot.dose >= 0 else {
                throw ValidationError("План «\(name)»: отрицательная доза в дне \(day)")
            }
            guard slot.times >= 1 else {
                throw ValidationError("План «\(name)»: times < 1 в дне \(day)")
            }
        }
    }
}

extension AppData {
    public func validate() throws {
        guard format.hasPrefix("mymeds-backup/") else {
            throw ValidationError("Неизвестный формат бэкапа: \(format)")
        }
        for plan in plans {
            try plan.validate()
        }

        var seen = Set<String>()
        for intake in intakes {
            guard let plan = plans.first(where: { $0.id == intake.planId }) else {
                throw ValidationError("Intake без плана: planId \(intake.planId)")
            }
            guard (1...plan.durationDays).contains(intake.day) else {
                throw ValidationError("Intake: день \(intake.day) вне диапазона плана «\(plan.name)»")
            }
            guard seen.insert("\(intake.planId.uuidString)#\(intake.day)").inserted else {
                throw ValidationError("Дубль Intake (planId, day=\(intake.day)) — должна быть одна запись")
            }
            if intake.status != nil {
                guard intake.takenAt != nil else {
                    throw ValidationError("Intake со статусом, но без takenAt (день \(intake.day))")
                }
            }
            if let dose = intake.actualDose, dose < 0 {
                throw ValidationError("Отрицательный actualDose (день \(intake.day))")
            }
            if let dose = intake.doseOverride, dose < 0 {
                throw ValidationError("Отрицательный doseOverride (день \(intake.day))")
            }
        }
        guard settings.notifyHorizonDays > 0 else {
            throw ValidationError("notifyHorizonDays должен быть > 0")
        }
    }
}
