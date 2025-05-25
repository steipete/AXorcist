// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "axPackage", // Renamed package slightly to avoid any confusion with executable name
    platforms: [
        .macOS(.v13) // macOS 13.0 or later
    ],
    products: [
        .library(name: "AXorcist", targets: ["AXorcist"]), // Product 'AXorcist' now comes from target 'AXorcist'
        .executable(name: "axorc", targets: ["axorc"]) // Product 'axorc' comes from target 'axorc'
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"), // Added swift-argument-parser
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0") // Added swift-testing
    ],
    targets: [
        .target(
            name: "AXorcist",
            dependencies: [],
            path: "Sources/AXorcist", // Be very direct about the source path
            exclude: [],             // Explicitly no excludes
            sources: nil             // Explicitly let SPM find all sources in the path
        ),
        .executableTarget(
            name: "axorc", // Executable target name
            dependencies: [
                "AXorcist", // Dependency restored to AXorcist
                .product(name: "ArgumentParser", package: "swift-argument-parser") // Added dependency product
            ],
            path: "Sources/axorc", // Explicit path
            sources: [
                "AXORCMain.swift",
                "Core/CommandExecutor.swift",
                "Core/InputHandler.swift",
                "Models/AXORCModels.swift"
            ]
        ),
        .testTarget(
            name: "AXorcistTests",
            dependencies: [
                "AXorcist", // Dependency restored to AXorcist
                .product(name: "Testing", package: "swift-testing") // Added swift-testing dependency
            ],
            path: "Tests/AXorcistTests" // Explicit path
            // Sources will be inferred by SPM
        )
    ]
)
