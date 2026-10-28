// swift-tools-version: 6.0
import PackageDescription
import Foundation

let cltPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let isGitHubActions = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
let testSwiftSettings: [SwiftSetting] = (!isGitHubActions && FileManager.default.fileExists(atPath: cltPluginPath))
    ? [.unsafeFlags(["-Xfrontend", "-plugin-path", "-Xfrontend", cltPluginPath])]
    : []

let package = Package(
    name: "OpenKeySwift",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "OpenKeySwiftCore", targets: ["OpenKeySwiftCore"]),
        .executable(name: "OpenKeySwiftApp", targets: ["OpenKeySwiftApp"])
    ],
    targets: [
        .target(
            name: "OpenKeySwiftCore",
            path: "Sources/OpenKeySwiftCore"
        ),
        .executableTarget(
            name: "OpenKeySwiftApp",
            dependencies: [
                "OpenKeySwiftCore"
            ],
            path: "Sources/OpenKeySwiftApp"
        ),
        .testTarget(
            name: "OpenKeySwiftTests",
            dependencies: [
                "OpenKeySwiftCore"
            ],
            path: "Tests/OpenKeySwiftTests",
            swiftSettings: testSwiftSettings
        )
    ]
)
