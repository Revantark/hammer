// swift-tools-version: 6.2
import PackageDescription

let releaseSize: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "Hammer",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "HammerCore", swiftSettings: releaseSize),
        .target(name: "HammerMac", dependencies: ["HammerCore"], swiftSettings: releaseSize),
        .executableTarget(name: "Hammer", dependencies: ["HammerCore", "HammerMac"], swiftSettings: releaseSize),
        .executableTarget(name: "HammerBench", dependencies: ["HammerCore", "HammerMac"]),
        .testTarget(name: "HammerCoreTests", dependencies: ["HammerCore"]),
        .testTarget(name: "HammerMacTests", dependencies: ["HammerMac", "HammerCore"]),
    ]
)
