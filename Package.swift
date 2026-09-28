// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDWatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PDWatch",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
