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
    dependencies: [
        .package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.9.1"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat.git", from: "0.52.0"),
    ],
    targets: [
        .executableTarget(
            name: "ContextHelper",
            dependencies: ["SwiftSodium"],
            path: "Sources"
        ),
        .testTarget(
            name: "ContextHelperTests",
            dependencies: ["ContextHelper"],
            path: "Tests"
        )
    ]
)
