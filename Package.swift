// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScrollDolmeng",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .systemLibrary(
            name: "MultitouchSupport"
        ),
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ScrollDolmeng",
            dependencies: ["MultitouchSupport"],
            linkerSettings: [
                .linkedFramework("MultitouchSupport"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
            ]
        ),
        .testTarget(
            name: "ScrollDolmengTests",
            dependencies: ["ScrollDolmeng"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
