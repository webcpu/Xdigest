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
        .executableTarget(
            name: "XdigestApp",
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
            name: "XdigestAppTests",
            dependencies: ["XdigestApp"],
            path: "Tests/XdigestAppTests"
        ),
    ]
)
