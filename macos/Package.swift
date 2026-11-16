// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaptureAccess",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CaptureAccess", targets: ["CaptureAccessMac"]),
        .executable(name: "CaptureAccessDemo", targets: ["CaptureAccessDemo"]),
        .executable(name: "CaptureAccessPageBridge", targets: ["CaptureAccessPageBridge"])
    ],
    targets: [
        .target(name: "CaptureCore"),
        .target(name: "PageCaptureCore"),
        .target(name: "UpdateCore"),
        .executableTarget(name: "CaptureAccessMac", dependencies: ["CaptureCore", "PageCaptureCore", "UpdateCore"]),
        .executableTarget(name: "CaptureAccessDemo"),
        .executableTarget(name: "CaptureAccessPageBridge", dependencies: ["PageCaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
        .testTarget(name: "PageCaptureCoreTests", dependencies: ["PageCaptureCore"]),
        .testTarget(name: "UpdateCoreTests", dependencies: ["UpdateCore"])
    ],
    swiftLanguageVersions: [.v5]
)
