// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaptureAccess",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CaptureAccess", targets: ["CaptureAccessMac"]),
        .executable(name: "CaptureAccessDemo", targets: ["CaptureAccessDemo"])
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "CaptureAccessMac", dependencies: ["CaptureCore"]),
        .executableTarget(name: "CaptureAccessDemo"),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"])
    ],
    swiftLanguageVersions: [.v5]
)
