// swift-tools-version: 5.10
import PackageDescription

// DesignSystem — внешний вид приложения (MED_APP_SPEC.md §12).
// Нативный Liquid Glass (iOS 26): glassEffect + системные материалы;
// все анимации — только через токены Motion. Без бизнес-логики и зависимостей.
let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
    ]
)
