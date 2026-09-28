import SwiftUI

// MARK: - Liquid Glass (нативный, iOS 26)
// glassEffect — системный материал; но форма задаётся ЯВНО: дефолтная форма
// системы — капсула, от неё карточки превращаются в блобы. Наша форма —
// скруглённый прямоугольник с радиусом из токенов Radius.
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tintColor: Color?

    public init(cornerRadius: CGFloat = Radius.card, tintColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        content.glassEffect(
            tintColor.map { Glass.regular.tint($0) } ?? .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

// MARK: - View Extension for Liquid Glass
public extension View {
    func liquidGlass(cornerRadius: CGFloat = Radius.card, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tintColor: tint))
    }
}