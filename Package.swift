// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchSlip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchSlip",
            path: "Sources/NotchSlip"
        )
    ]
)