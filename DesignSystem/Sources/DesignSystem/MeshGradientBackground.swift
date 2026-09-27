import SwiftUI

/// Фон приложения (порт из UnicTracker, развязан от их DataStore/темы:
/// палитра — константы Palette, анимация — токен Motion.ambient).
public struct MeshGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateGlow = false

    public var ambientGlow: Bool

    public init(ambientGlow: Bool = true) {
        self.ambientGlow = ambientGlow
    }

    private var isDark: Bool { colorScheme == .dark }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: Palette.background(isDark: isDark),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if ambientGlow {
                // Ambient Luminous Liquid Orbs
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Circle()
                        .fill(Palette.primary.opacity(isDark ? 0.22 : 0.12))
                        .frame(width: w * 0.9, height: w * 0.9)
                        .blur(radius: 70)
                        .offset(
                            x: animateGlow ? -w * 0.2 : w * 0.1,
                            y: animateGlow ? -h * 0.15 : -h * 0.05
                        )

                    Circle()
                        .fill(Palette.secondary.opacity(0.18))
                        .frame(width: w * 0.85, height: w * 0.85)
                        .blur(radius: 80)
                        .offset(
                            x: animateGlow ? w * 0.3 : -w * 0.1,
                            y: animateGlow ? h * 0.4 : h * 0.2
                        )

                    Circle()
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: w * 0.6, height: w * 0.6)
                        .blur(radius: 60)
                        .offset(
                            x: animateGlow ? 0 : w * 0.2,
                            y: animateGlow ? h * 0.7 : h * 0.6
                        )
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(Motion.ambient) {
                animateGlow.toggle()
            }
        }
    }
}
