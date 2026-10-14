// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GymaCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "GymaCore", targets: ["GymaCore"])],
    targets: [.target(name: "GymaCore"), .testTarget(name: "GymaCoreTests", dependencies: ["GymaCore"])],
    swiftLanguageModes: [.v5]
)
