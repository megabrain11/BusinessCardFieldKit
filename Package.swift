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
  ],
  targets: [
    .target(name: "CardFieldCore"),
    .target(name: "AppleVisionAdapter", dependencies: ["CardFieldCore"]),
    .target(name: "CardFieldEvaluation", dependencies: ["CardFieldCore"]),
    .executableTarget(name: "card-field-eval", dependencies: ["CardFieldEvaluation"]),
    .testTarget(
      name: "CardFieldCoreTests",
      dependencies: ["CardFieldCore", "CardFieldEvaluation"]
    ),
    .testTarget(name: "AppleVisionAdapterTests", dependencies: ["AppleVisionAdapter"]),
  ]
)
