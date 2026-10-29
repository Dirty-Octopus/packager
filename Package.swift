// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Packager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Packager",
            path: "Sources/Packager",
            resources: [.copy("Resources/Version.txt")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(name: "PackagerTests", dependencies: ["Packager"], path: "Tests/PackagerTests")
    ]
)
