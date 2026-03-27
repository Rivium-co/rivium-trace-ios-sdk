// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RiviumTrace",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_14),
        .tvOS(.v12),
        .watchOS(.v5)
    ],
    products: [
        .library(
            name: "RiviumTrace",
            targets: ["RiviumTrace"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RiviumTrace",
            dependencies: [],
            path: "Sources/RiviumTrace"
        ),
        .testTarget(
            name: "RiviumTraceTests",
            dependencies: ["RiviumTrace"],
            path: "Tests/RiviumTraceTests"
        ),
    ],
    swiftLanguageVersions: [.v5, .version("6")]
)
