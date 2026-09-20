// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LARM",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LARMCore",
            path: "Sources/LARMCore",
            resources: [.copy("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "LARM",
            dependencies: ["LARMCore"],
            path: "Sources/LARM"
        ),
        .executableTarget(
            name: "larm-hook",
            dependencies: ["LARMCore"],
            path: "Sources/larm-hook"
        ),
        .executableTarget(
            name: "larm-verify",
            dependencies: ["LARMCore"],
            path: "Sources/larm-verify"
        ),
        .testTarget(
            name: "LARMCoreTests",
            dependencies: ["LARMCore"],
            path: "Tests/LARMCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
