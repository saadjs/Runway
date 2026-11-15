// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Runway",
    platforms: [.macOS(.v26)],
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
