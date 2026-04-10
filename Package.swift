// swift-tools-version: 6.0

import Foundation
import PackageDescription

private let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let infoPlistPath = packageRoot
    .appendingPathComponent("Sources/XdigestApp/Info.plist").path

let package = Package(
    name: "Xdigest",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Xdigest", targets: ["XdigestApp"]),
    ],
    targets: [
        .target(
            name: "XdigestCore",
            path: "Sources/XdigestCore"
        ),
        .target(
            name: "BirdService",
            dependencies: ["XdigestCore"],
            path: "Sources/BirdService"
        ),
        .target(
            name: "ScorerService",
            dependencies: ["XdigestCore"],
            path: "Sources/ScorerService"
        ),
        .target(
            name: "DigestService",
            dependencies: ["XdigestCore"],
            path: "Sources/DigestService"
        ),
        .target(
            name: "ServerService",
            dependencies: ["XdigestCore"],
            path: "Sources/ServerService"
        ),
        .target(
            name: "Pipeline",
            dependencies: ["XdigestCore", "BirdService", "ScorerService", "DigestService"],
            path: "Sources/Pipeline"
        ),
        .executableTarget(
            name: "XdigestApp",
            dependencies: ["XdigestCore", "BirdService", "ScorerService", "DigestService", "ServerService", "Pipeline"],
            path: "Sources/XdigestApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ]),
            ]
        ),
        .testTarget(
            name: "XdigestCoreTests",
            dependencies: ["XdigestCore"],
            path: "Tests/XdigestCoreTests"
        ),
        .testTarget(
            name: "BirdServiceTests",
            dependencies: ["BirdService", "XdigestCore"],
            path: "Tests/BirdServiceTests"
        ),
        .testTarget(
            name: "ScorerServiceTests",
            dependencies: ["ScorerService", "XdigestCore"],
            path: "Tests/ScorerServiceTests"
        ),
        .testTarget(
            name: "DigestServiceTests",
            dependencies: ["DigestService", "XdigestCore"],
            path: "Tests/DigestServiceTests"
        ),
        .testTarget(
            name: "ServerServiceTests",
            dependencies: ["ServerService", "XdigestCore"],
            path: "Tests/ServerServiceTests"
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline", "XdigestCore"],
            path: "Tests/PipelineTests"
        ),
    ]
)
