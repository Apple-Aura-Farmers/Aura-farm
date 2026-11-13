// swift-tools-version: 5.9

import PackageDescription

/// What the field app and the farm manager share: the soil report one hands to the other.
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
