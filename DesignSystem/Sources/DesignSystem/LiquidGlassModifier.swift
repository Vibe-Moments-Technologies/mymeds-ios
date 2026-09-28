import SwiftUI

// MARK: - Liquid Glass (нативный, iOS 26)
// glassEffect — системный преломляющий материал: спекуляры, борды и
// анимации состояния рисует ОС. Мы выбираем только tint и форму.
// ponytail: самодельные шейдеры-имитации удалены; фолбэк не нужен —
// floor приложения = iOS 26.
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tintColor: Color?

    public init(cornerRadius: CGFloat = 20, tintColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        content
            .glassEffect(
                tintColor.map { Glass.regular.tint($0) } ?? .regular
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - View Extension for Liquid Glass
public extension View {
    func liquidGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tintColor: tint))
    }
}
