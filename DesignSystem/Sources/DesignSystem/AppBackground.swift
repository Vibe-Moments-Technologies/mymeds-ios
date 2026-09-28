import SwiftUI

/// Фон приложения: однотонный, следует системной теме (светлая/тёмная).
/// Стекло Liquid Glass само подстраивается под то, что под ним — пестрота под
/// ним только мешает контрасту, поэтому заливка ровная.
public struct AppBackground: View {
    public init() {}

    public var body: some View {
        Palette.background
            .ignoresSafeArea()
    }
}