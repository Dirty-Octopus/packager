// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Packager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Packager",
            path: "Sources/Packager",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
