// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "Tuck",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(
      name: "Tuck",
      path: "Sources/Tuck",
      linkerSettings: [.linkedFramework("Carbon")]
    ),
    .testTarget(
      name: "TuckTests",
      dependencies: ["Tuck"],
      path: "Tests/TuckTests"
    ),
  ]
)
