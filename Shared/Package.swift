// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BasinShared",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "BasinShared", targets: ["BasinShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
    ],
    targets: [
        .target(
            name: "BasinShared",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/BasinShared"
        ),
        .testTarget(
            name: "BasinSharedTests",
            dependencies: ["BasinShared"],
            path: "Tests/BasinSharedTests"
        ),
    ]
)
