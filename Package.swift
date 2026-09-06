// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BusinessCardFieldKit",
  platforms: [
    .macOS(.v13),
    .iOS(.v17),
  ],
  products: [
    .library(name: "CardFieldCore", targets: ["CardFieldCore"]),
    .library(name: "AppleVisionAdapter", targets: ["AppleVisionAdapter"]),
    .library(name: "CardFieldEvaluation", targets: ["CardFieldEvaluation"]),
    .executable(name: "card-field-eval", targets: ["card-field-eval"]),
    .executable(name: "card-field-scan", targets: ["card-field-scan"]),
    .executable(name: "card-field-benchmark", targets: ["card-field-benchmark"]),
    .executable(
      name: "card-field-private-benchmark",
      targets: ["card-field-private-benchmark"]
    ),
  ],
  targets: [
    .target(name: "CardFieldCore"),
    .target(name: "AppleVisionAdapter", dependencies: ["CardFieldCore"]),
    .target(name: "CardFieldEvaluation", dependencies: ["CardFieldCore"]),
    .target(
      name: "AppleVisionBenchmarking",
      dependencies: ["AppleVisionAdapter", "CardFieldCore"]
    ),
    .executableTarget(name: "card-field-eval", dependencies: ["CardFieldEvaluation"]),
    .executableTarget(
      name: "card-field-scan",
      dependencies: ["AppleVisionAdapter", "CardFieldCore"]
    ),
    .executableTarget(
      name: "card-field-benchmark",
      dependencies: ["AppleVisionBenchmarking"]
    ),
    .executableTarget(
      name: "card-field-private-benchmark",
      dependencies: ["AppleVisionBenchmarking"]
    ),
    .testTarget(
      name: "CardFieldCoreTests",
      dependencies: ["CardFieldCore", "CardFieldEvaluation"]
    ),
    .testTarget(
      name: "AppleVisionAdapterTests",
      dependencies: ["AppleVisionAdapter", "AppleVisionBenchmarking"]
    ),
  ]
)
