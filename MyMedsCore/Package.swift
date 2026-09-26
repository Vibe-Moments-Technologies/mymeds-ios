// swift-tools-version: 5.10
import PackageDescription

// Ядро MyMeds (MED_APP_SPEC.md §12): модель, резолв дня, хранение, кодеки.
// Без SwiftUI. Общий для app, виджета и Intent Handler.
let package = Package(
    name: "MyMedsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),  // для `swift test` на хост-машине/CI без симулятора
    ],
    products: [
        .library(name: "MyMedsCore", targets: ["MyMedsCore"]),
    ],
    targets: [
        .target(name: "MyMedsCore"),
        .testTarget(name: "MyMedsCoreTests", dependencies: ["MyMedsCore"]),
    ]
)
