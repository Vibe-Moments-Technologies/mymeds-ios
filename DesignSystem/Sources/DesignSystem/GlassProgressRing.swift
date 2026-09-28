import SwiftUI

public struct GlassProgressRing: View {
    public var progress: Double // 0.0 ... 1.0
    public var size: CGFloat
    public var strokeWidth: CGFloat
    public var accentColors: [Color]
    public var caption: String

    public init(
        progress: Double,
        size: CGFloat = 84,
        strokeWidth: CGFloat = 8,
        accentColors: [Color] = [Palette.primary, Color.blue, Palette.secondary],
        caption: String = "готовность"
    ) {
        self.progress = max(0.0, min(1.0, progress))
        self.size = size
        self.strokeWidth = strokeWidth
        self.accentColors = accentColors
        self.caption = caption
    }

    public var body: some View {
        ZStack {
            // Трек: тонкий, читаемый и на светлом, и на тёмном фоне
            Circle()
                .stroke(
                    Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Мягкое свечение прогресса (единственная «украшательная» часть)
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth + 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 4)
                .opacity(0.45)

            // Основной штрих прогресса
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Motion.progress, value: progress)

            // Центр: цвет — системный primary, а не белый (на светлой теме белый невидим)
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(caption)
                    .font(.system(size: size * 0.11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
