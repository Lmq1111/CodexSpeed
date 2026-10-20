// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CodexSpeed", platforms: [.macOS(.v26)],
    products: [.executable(name: "CodexSpeed", targets: ["CodexSpeed"])],
    dependencies: [.package(path: "Vendor/swift-tiktoken")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MonitorCore", dependencies: ["CSQLite", .product(name: "SwiftTiktoken", package: "swift-tiktoken")], resources: [.copy("o200k_base.tiktoken")]),
        .executableTarget(name: "CodexSpeed", dependencies: ["MonitorCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
        .testTarget(name: "CodexSpeedTests", dependencies: ["CodexSpeed"])
    ], swiftLanguageModes: [.v5]
)
