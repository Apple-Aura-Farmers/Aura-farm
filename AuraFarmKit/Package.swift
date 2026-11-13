// swift-tools-version: 5.9

import PackageDescription

/// What the field app shares across its code: the organism group names a farmer would use.
///
/// Foundation only, so it builds anywhere.
let package = Package(
    name: "AuraFarmKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AuraFarmKit", targets: ["AuraFarmKit"])
    ],
    targets: [
        .target(name: "AuraFarmKit")
    ]
)
