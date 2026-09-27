import SwiftUI
import MyMedsCore
import DesignSystem

// UI-представление статусов и доз — единственный источник (правило §12:
// вторая копия маппинга = вынести сюда).

extension IntakeStatus {
    var label: String {
        switch self {
        case .taken: return "принято"
        case .skipped: return "пропущено"
        case .missed: return "не принято"
        case .pending: return "ожидает"
        case .scheduled: return "запланировано"
        }
    }

    var icon: String {
        switch self {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .missed: return "exclamationmark.triangle.fill"
        case .pending: return "clock.fill"
        case .scheduled: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .taken: return .green
        case .skipped: return .orange
        case .missed: return .red
        case .pending: return .cyan
        case .scheduled: return .gray
        }
    }
}

extension Medication {
    /// Акцентный цвет: colorHex лекарства, иначе палитра по умолчанию.
    var accent: Color {
        guard let hex = colorHex?.trimmingCharacters(in: .whitespaces),
              hex.count == 7, hex.hasPrefix("#") else { return Palette.primary }
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension CivilDate {
    /// «17 мая, воскресенье» — заголовок дня в UI.
    var humanText: String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return description }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, EEEE"
        return formatter.string(from: date)
    }
}
