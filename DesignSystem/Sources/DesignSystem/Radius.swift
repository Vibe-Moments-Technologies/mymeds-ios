import SwiftUI

// Радиусы и метрики (§12: один набор токенов, никаких ad-hoc чисел в экранах).
// Форма скругления одна на приложение: квадраты со скруглением, без капсул —
// капсулы хороши для чипов-переключателей, но не для карточек и бейджей.
public enum Radius {
    public static let card: CGFloat = 18
    public static let cell: CGFloat = 10
    public static let chip: CGFloat = 8
    public static let field: CGFloat = 10
}