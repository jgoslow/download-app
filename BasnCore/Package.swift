// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BasnCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BasnCore", targets: ["BasnCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Clipy/Sauce", branch: "master"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(path: "../Shared"),
    ],
    targets: [
	    .target(
	        name: "BasnCore",
	        dependencies: [
	            "Sauce",
	            .product(name: "BasinShared", package: "Shared"),
	            .product(name: "Dependencies", package: "swift-dependencies"),
	            .product(name: "DependenciesMacros", package: "swift-dependencies"),
	            .product(name: "Logging", package: "swift-log"),
	        ],
	        path: "Sources/BasnCore",
	        linkerSettings: [
	            .linkedFramework("IOKit")
	        ]
	    ),
        .testTarget(
            name: "BasnCoreTests",
            dependencies: ["BasnCore"],
            path: "Tests/BasnCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
