// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EEG", platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1)], products: [.library(name: "EEGCore", targets: ["EEGCore"]), .executable(name: "EEG", targets: ["EEGApp"])], targets: [.target(name: "EEGCore"), .executableTarget(name: "EEGApp", dependencies: ["EEGCore"]), .testTarget(name: "EEGCoreTests", dependencies: ["EEGCore"])])
