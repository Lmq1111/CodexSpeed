// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "swift-tiktoken",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(
      name: "SwiftTiktoken",
      targets: ["SwiftTiktoken"],
    ),
  ],
  targets: [
    .target(
      name: "SwiftTiktoken",
      path: "Sources/SwiftTiktoken"
    ),
    .executableTarget(
      name: "Benchmark",
      dependencies: ["SwiftTiktoken"],
      path: "Sources/Benchmark"
    ),
    .testTarget(
      name: "SwiftTiktokenTests",
      dependencies: ["SwiftTiktoken"],
      path: "Tests/SwiftTiktokenTests"
    ),
  ],
)
