// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OpenNimbot",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "OpenNimbot", targets: ["OpenNimbot"])],
  targets: [
    .executableTarget(name: "OpenNimbot"),
    .testTarget(name: "OpenNimbotTests", dependencies: ["OpenNimbot"]),
  ],
  swiftLanguageModes: [.v5]
)
