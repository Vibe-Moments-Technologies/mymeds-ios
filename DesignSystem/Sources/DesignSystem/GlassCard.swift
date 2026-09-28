import SwiftUI

/// Карточка: один компонент внешнего вида (§12). Форма — скруглённый
/// прямоугольник (Radius.card), не капсула; tint подмешивается в стекло.
public struct GlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var tint: Color?
    @ViewBuilder public var content: Content

    public init(
        cornerRadius: CGFloat = Radius.card,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .liquidGlass(cornerRadius: cornerRadius, tint: tint)
    }
}