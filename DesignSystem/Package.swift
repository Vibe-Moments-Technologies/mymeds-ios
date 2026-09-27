// swift-tools-version: 5.10
import PackageDescription

// DesignSystem — внешний вид приложения (MED_APP_SPEC.md §12).
// Glass-компоненты — порт из UnicTracker; все анимации — только через токены Motion.
// Без бизнес-логики и без зависимости от MyMedsCore.
let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),  // чтобы пакет собирался на хосте; хаптика guarded canImport(UIKit)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
    ]
)
