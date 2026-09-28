import SwiftUI

public struct GlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var tint: Color?
    @ViewBuilder public var content: Content

    public init(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        glow: Double = 0.4,
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
