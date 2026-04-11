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
    dependencies: [
        // Sparkle owns the full update lifecycle: download, signature
        // verification, in-place replacement, and relaunch. The appcast
        // URL and EdDSA public key live in Info.plist; release.sh
        // publishes new versions by updating appcast.xml on origin/main.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
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
            dependencies: [
                "XdigestCore", "BirdService", "ScorerService", "DigestService",
                "ServerService", "Pipeline",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
