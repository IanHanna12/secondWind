// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecondWind",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SecondWindCore", targets: ["SecondWindCore"]),
        .library(name: "SecondWindApplication", targets: ["SecondWindApplication"]),
        .library(name: "SecondWindInfrastructure", targets: ["SecondWindInfrastructure"]),
        .library(name: "SecondWindPlatform", targets: ["SecondWindPlatform"]),
        .library(name: "SecondWindSnapshots", targets: ["SecondWindSnapshots"]),
        .executable(name: "SecondWind", targets: ["SecondWind"])
    ],
    targets: [
        .target(name: "SecondWindCore", path: "Sources/SecondWindCore"),
        .target(name: "SecondWindApplication", dependencies: ["SecondWindCore"], path: "Sources/SecondWindApplication"),
        .target(name: "SecondWindInfrastructure", dependencies: ["SecondWindCore"], path: "Sources/SecondWindInfrastructure"),
        .target(name: "SecondWindPlatform", dependencies: ["SecondWindCore", "SecondWindInfrastructure"], path: "Sources/SecondWindPlatform"),
        .target(name: "SecondWindSnapshots", dependencies: ["SecondWindCore"], path: "Sources/SecondWindSnapshots"),
        .executableTarget(name: "SecondWind", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindInfrastructure", "SecondWindPlatform", "SecondWindSnapshots"], path: "Sources/CLI"),
        .testTarget(name: "SecondWindCoreTests", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindInfrastructure", "SecondWindPlatform", "SecondWindSnapshots"], path: "Tests/SecondWindCoreTests")
    ]
)
