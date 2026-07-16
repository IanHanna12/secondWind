// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecondWind",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SecondWindCore", targets: ["SecondWindCore"]),
        .library(name: "SecondWindApplication", targets: ["SecondWindApplication"]),
        .library(name: "SecondWindSystem", targets: ["SecondWindSystem"]),
        .library(name: "SecondWindPersistence", targets: ["SecondWindPersistence"]),
        .library(name: "SecondWindPlatform", targets: ["SecondWindPlatform"]),
        .executable(name: "SecondWind", targets: ["SecondWind"])
    ],
    targets: [
        .target(name: "SecondWindCore", path: "Sources/SecondWindCore"),
        .target(name: "SecondWindApplication", dependencies: ["SecondWindCore"], path: "Sources/SecondWindApplication"),
        .target(name: "SecondWindSystem", dependencies: ["SecondWindCore"], path: "Sources/SecondWindSystem"),
        .target(name: "SecondWindPersistence", dependencies: ["SecondWindCore", "SecondWindSystem"], path: "Sources/SecondWindPersistence"),
        .target(name: "SecondWindPlatform", dependencies: ["SecondWindCore", "SecondWindSystem"], path: "Sources/SecondWindPlatform"),
        .executableTarget(name: "SecondWind", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindSystem", "SecondWindPersistence", "SecondWindPlatform"], path: "Sources/CLI"),
        .testTarget(name: "SecondWindCoreTests", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindSystem", "SecondWindPersistence", "SecondWindPlatform"], path: "Tests/SecondWindCoreTests")
    ]
)
