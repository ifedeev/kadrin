// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Screenshot",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "Screenshot", targets: ["Screenshot"])],
  targets: [
    .target(name: "ScreenshotCore"),
    .executableTarget(name: "Screenshot", dependencies: ["ScreenshotCore"]),
    .testTarget(name: "ScreenshotCoreTests", dependencies: ["ScreenshotCore"]),
    .testTarget(name: "ScreenshotAppTests", dependencies: ["Screenshot", "ScreenshotCore"]),
  ],
  swiftLanguageModes: [.v5]
)
