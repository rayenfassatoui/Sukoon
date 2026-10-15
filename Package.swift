// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sukoon",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Sukoon", targets: ["Sukoon"]),
        .library(name: "SukoonCore", targets: ["SukoonCore"])
    ],
    targets: [
        .target(name: "SukoonCore", resources: [.process("Resources")]),
        .executableTarget(name: "Sukoon", dependencies: ["SukoonCore"], resources: [.copy("Resources")]),
        .testTarget(name: "SukoonCoreTests", dependencies: ["SukoonCore"])
    ]
)
