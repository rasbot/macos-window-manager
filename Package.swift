// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WindowDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DockCore", targets: ["DockCore"]),
        .executable(name: "WindowDock", targets: ["WindowDock"])
    ],
    targets: [
        .target(name: "DockCore"),
        .executableTarget(
            name: "WindowDock",
            dependencies: ["DockCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ColorSync")
            ]
        ),
        .testTarget(name: "DockCoreTests", dependencies: ["DockCore"])
    ],
    swiftLanguageModes: [.v5]
)
