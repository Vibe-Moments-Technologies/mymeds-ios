import SwiftUI

/// Палитра по умолчанию — порт пресета cyberGlass из UnicTracker.
/// Per-лекарство цвета берутся из `Medication.colorHex` (модель), не отсюда.
public enum Palette {
    public static let primary = Color(red: 0.0, green: 0.78, blue: 0.95)
    public static let secondary = Color(red: 0.55, green: 0.2, blue: 1.0)

    public static func background(isDark: Bool) -> [Color] {
        isDark
            ? [Color(red: 0.05, green: 0.05, blue: 0.12), Color(red: 0.02, green: 0.02, blue: 0.06)]
            : [Color(red: 0.93, green: 0.96, blue: 0.99), Color(red: 0.88, green: 0.92, blue: 0.97)]
    }
}
