// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ContextHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ContextHelper", targets: ["ContextHelper"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ContextHelper",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-framework", "ScreenCaptureKit"]),
                .unsafeFlags(["-framework", "VideoToolbox"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
            ]
        ),
        .testTarget(
            name: "ContextHelperTests",
            dependencies: ["ContextHelper"],
            path: "Tests"
        )
    ]
)
