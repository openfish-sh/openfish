// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Koifish",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Koifish",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Koifish",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KoifishTests",
            dependencies: ["Koifish"],
            path: "Tests/KoifishTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
