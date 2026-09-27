import SwiftUI
import DesignSystem

/// Маскот (§12) — визуализация streak, ничего больше: состояние выводится из
/// числа, без хранения и новых сущностей. Анимации — токены Motion.
/// Уровни: 0 — потух, 1–6 — жив, 7/30/100 — огонь растёт.
///
/// // ponytail: настроения/квесты/магазин = уже не визуализация streak.
/// // Не добавлять состояние, пока не попросят.
struct MascotView: View {
    let streak: Int
    var size: CGFloat = 1.0   // масштаб (1 — Home, 1.6 — аналитика)

    private var level: Int {
        if streak >= 100 { return 4 }
        if streak >= 30 { return 3 }
        if streak >= 7 { return 2 }
        if streak >= 1 { return 1 }
        return 0
    }

    private var symbol: String { level == 0 ? "flame" : "flame.fill" }

    private var color: Color {
        switch level {
        case 0: return .gray.opacity(0.5)
        case 1: return .orange.opacity(0.8)
        case 2: return .orange
        case 3: return Color(red: 1.0, green: 0.45, blue: 0.2)
        default: return Color(red: 1.0, green: 0.3, blue: 0.4)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: (22 + CGFloat(level) * 4) * size))
                .foregroundStyle(level == 0
                                 ? AnyShapeStyle(color)
                                 : AnyShapeStyle(LinearGradient(
                                     colors: [color, .yellow.opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom)))
                .symbolEffect(.pulse, options: .repeating, isActive: level > 0)
                .contentTransition(.symbolEffect(.replace))
                .animation(Motion.celebrate, value: level)
            Text(streak == 0 ? "потух" : "\(streak) дн.")
                .font(.system(size: 11 * min(size, 1.3), weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(Motion.statusChange, value: streak)
        }
        .accessibilityLabel(level == 0
                            ? "Серия сброшена"
                            : "Серия \(streak) дней, уровень \(level)")
    }
}
