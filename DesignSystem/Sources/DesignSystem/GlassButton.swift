import SwiftUI

/// Нативная glass-кнопка iOS 26: системные состояния (highlight, tint,
/// анимации) даёт `.buttonStyle(.glass)`; хаптик остаётся наш (Motion-токены).
public struct GlassButtonStyle: ButtonStyle {
    public var tint: Color?
    public var cornerRadius: CGFloat   // не используется системным стилем; оставлен для совместимости вызовов
    public var isProminent: Bool       // при true подмешивает tint; иначе прозрачное стекло

    public init(tint: Color? = nil, cornerRadius: CGFloat = 16, isProminent: Bool = false) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .buttonStyle(.glass)   // нативный Liquid Glass в интерактиве
            .tint(isProminent ? (tint ?? Color.blue) : tint)
            .onChange(of: configuration.isPressed) { _, isPressed in
                #if canImport(UIKit)
                if isPressed {
                    HapticManager.shared.buttonPress()
                }
                #endif
            }
    }
}
