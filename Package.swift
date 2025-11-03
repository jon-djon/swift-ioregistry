// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-ioregistry",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftIORegistry",
            targets: ["SwiftIORegistry"]
        ),
        .executable(
            name: "ioreg",
            targets: ["ioreg"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftIORegistry",
            dependencies: [ ],
            path: "Sources/SwiftIORegistry"
        ),
        .executableTarget(name: "ioreg", dependencies: [
            "SwiftIORegistry",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(
            name: "SwiftIORegistryTests",
            dependencies: [
                "SwiftIORegistry",
            ]
        ),
    ]
)
