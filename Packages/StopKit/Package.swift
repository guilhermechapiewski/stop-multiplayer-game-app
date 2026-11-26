// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StopKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "StopCore", targets: ["StopCore"]),
        .library(name: "StopNetworking", targets: ["StopNetworking"]),
        .library(name: "StopSession", targets: ["StopSession"]),
        .library(name: "StopSimulation", targets: ["StopSimulation"]),
        .library(name: "StopTestSupport", targets: ["StopTestSupport"]),
    ],
    targets: [
        .target(name: "StopCore"),
        .target(name: "StopNetworking"),
        .target(name: "StopSession", dependencies: ["StopCore", "StopNetworking"]),
        .target(name: "StopSimulation", dependencies: ["StopSession"]),
        .target(name: "StopTestSupport", dependencies: ["StopCore"]),
        .testTarget(name: "StopCoreTests", dependencies: ["StopCore", "StopTestSupport"]),
        .testTarget(name: "StopNetworkingTests", dependencies: ["StopNetworking", "StopTestSupport"]),
        .testTarget(name: "StopSessionTests", dependencies: ["StopSession", "StopSimulation", "StopTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
