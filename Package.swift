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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "SukoonCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "Sukoon",
            dependencies: ["SukoonCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SukoonCoreTests", dependencies: ["SukoonCore"])
    ]
)
