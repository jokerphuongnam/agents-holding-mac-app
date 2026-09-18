// swift-tools-version: 5.9
import PackageDescription

/// Local SPM package whose only job is to pull SwiftGen into the repo’s
/// `.build` / checkouts so `Scripts/generate.sh` can `swift run` it —
/// no Homebrew / global install required.
let package = Package(
    name: "BuildTools",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftGen/SwiftGen.git", from: "6.6.3"),
    ],
    targets: [
        // Empty target so the package resolves & builds dependency graph.
        .target(
            name: "BuildTools",
            path: "Sources/BuildTools"
        ),
    ]
)
