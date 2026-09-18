// swift-tools-version: 5.9
import PackageDescription

/// Pulls build CLIs into the repo via SPM so `Scripts/generate.sh` needs only
/// a Swift toolchain — no Homebrew (`swiftgen` / `xcodegen`).
let package = Package(
    name: "BuildTools",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftGen/SwiftGen.git", from: "6.6.3"),
        .package(url: "https://github.com/yonaskolb/XcodeGen.git", from: "2.44.0"),
    ],
    targets: [
        .target(
            name: "BuildTools",
            path: "Sources/BuildTools"
        ),
    ]
)
