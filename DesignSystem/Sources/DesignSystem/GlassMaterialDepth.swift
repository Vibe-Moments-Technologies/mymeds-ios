import SwiftUI

/// Интенсивность стекла (порт из UnicTracker).
public enum GlassMaterialDepth: String, CaseIterable, Identifiable {
    case ultraLiquid = "Ultra Liquid (26/27 Refractive)"
    case frostedDeep = "Frosted Deep (Матовое)"
    case crystalClear = "Crystal Clear (Прозрачное)"

    public var id: String { rawValue }

    public var surfaceOpacity: Double {
        switch self {
        case .ultraLiquid: return 0.14
        case .frostedDeep: return 0.22
        case .crystalClear: return 0.08
        }
    }

    public var borderOpacity: Double {
        switch self {
        case .ultraLiquid: return 0.35
        case .frostedDeep: return 0.25
        case .crystalClear: return 0.18
        }
    }
}
