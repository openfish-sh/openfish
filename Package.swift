// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Koifish",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Koifish",
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
