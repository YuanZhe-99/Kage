// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KageController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KageController", targets: ["KageController"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KageController",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-framework", "VideoToolbox"]),
                .unsafeFlags(["-framework", "Metal"]),
                .unsafeFlags(["-framework", "MetalKit"]),
            ]
        ),
        .testTarget(
            name: "KageControllerTests",
            dependencies: ["KageController"],
            path: "Tests"
        )
    ]
)
