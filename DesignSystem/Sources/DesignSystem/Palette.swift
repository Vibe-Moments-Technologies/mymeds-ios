import SwiftUI

/// Единая палитра. Per-лекарство цвета берутся из `Medication.colorHex` (модель).
/// Все значения — семантические: фон и текст следуют системной теме автоматически.
public enum Palette {
    public static let primary = Color(red: 0.0, green: 0.78, blue: 0.95)
    public static let secondary = Color(red: 0.55, green: 0.2, blue: 1.0)

    /// Однотонный фон (systemGroupedBackground): светлая — #F2F2F7, тёмная — #000.
    public static let background = Color(uiColor: .systemGroupedBackground)
    /// Фон карточек/полей поверх стекла.
    public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}