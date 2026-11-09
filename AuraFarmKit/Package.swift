// swift-tools-version: 5.9

import PackageDescription

/// What the app is built on that needs no UI: the soil report, the NPK advice, field outlines.
///
/// Foundation only, so it builds and tests anywhere, including `swift test` on Linux CI.
let package = Package(
    name: "AuraFarmKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AuraFarmKit", targets: ["AuraFarmKit"])
    ],
    targets: [
        .target(name: "AuraFarmKit"),
        .testTarget(name: "AuraFarmKitTests", dependencies: ["AuraFarmKit"]),
    ]
)
