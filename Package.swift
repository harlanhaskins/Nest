// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Nest",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "nest", targets: ["NestCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "NestCLI",
            dependencies: [
                "Nest",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "Nest",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .testTarget(
            name: "NestTests",
            dependencies: ["Nest"]
        ),
    ]
)
