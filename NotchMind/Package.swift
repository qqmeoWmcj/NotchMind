// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchMind",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "NotchMind", targets: ["NotchMind"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchMind",
            path: "Sources/NotchMind",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "NotchMindTests",
            dependencies: ["NotchMind"],
            path: "Tests/NotchMindTests"
        ),
    ]
)
