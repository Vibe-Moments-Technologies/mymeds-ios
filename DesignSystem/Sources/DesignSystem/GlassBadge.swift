import SwiftUI

/// Универсальный бейдж статуса: один компонент для Home, деталей дня и календаря
/// (§12: одинаковые элементы строятся одним компонентом). Нативный Liquid Glass.
public struct GlassBadge: View {
    public var label: String
    public var icon: String?
    public var color: Color

    public init(label: String, icon: String? = nil, color: Color) {
        self.label = label
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlass(cornerRadius: 12, tint: color)
    }
}
