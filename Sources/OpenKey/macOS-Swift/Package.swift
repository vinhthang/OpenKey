// swift-tools-version: 6.0
import PackageDescription

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
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-plugin-path",
                    "-Xfrontend", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
                ])
            ]
        )
    ]
)
