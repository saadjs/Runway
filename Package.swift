// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Runway",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Runway",
            path: "Sources/Runway",
            resources: [
                .copy("Resources/claude.pdf"),
                .copy("Resources/codex.pdf"),
                .copy("Resources/opencode.pdf"),
            ],
            swiftSettings: [
                // Pragmatic: avoid fighting strict-concurrency diagnostics in a small app.
                .swiftLanguageMode(.v5),
            ]),
        .testTarget(
            name: "RunwayTests",
            dependencies: ["Runway"],
            path: "Tests/RunwayTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]),
    ])
