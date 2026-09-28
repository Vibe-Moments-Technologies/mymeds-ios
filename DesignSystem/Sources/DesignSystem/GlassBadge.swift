import SwiftUI

/// Бейдж статуса/счётчика: одна строка, скруглённый прямоугольник, без стекла
/// (стекло на мелких плашках даёт «мыло» и ломает перенос строк).
/// Один компонент на Home, детали дня, план, аналитику и календарь (§12).
public struct GlassBadge: View {
    public var label: String
    public var icon: String?
    public var color: Color
    public var compact: Bool

    public init(label: String, icon: String? = nil, color: Color, compact: Bool = false) {
        self.label = label
        self.icon = icon
        self.color = color
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .fixedSize(horizontal: true, vertical: false)   // никогда не рвётся по слогам
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(color.opacity(0.16))
        )
    }
}