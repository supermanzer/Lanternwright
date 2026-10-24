// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lanternwright",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Lanternwright",
            path: "Sources/Lanternwright",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ],
    swiftLanguageModes: [.v5]
)
