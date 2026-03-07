// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "RiviumTraceExample",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    dependencies: [
        .package(name: "RiviumTrace", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "RiviumTraceExample",
            dependencies: ["RiviumTrace"],
            path: "RiviumTraceExample"
        ),
    ]
)
