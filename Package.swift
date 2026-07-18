// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecondWind",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SecondWindCore", targets: ["SecondWindCore"]),
        .library(name: "SecondWindApplication", targets: ["SecondWindApplication"]),
        .library(name: "SecondWindPersistence", targets: ["SecondWindPersistence"]),
        .library(name: "SecondWindMacOS", targets: ["SecondWindMacOS"]),
        .executable(name: "SecondWind", targets: ["SecondWindUI"])
    ],
    targets: [
        .target(name: "SecondWindCore", path: "Sources/Core"),
        .target(name: "SecondWindApplication", dependencies: ["SecondWindCore"], path: "Sources/Application"),
        .target(name: "SecondWindMacOS", dependencies: ["SecondWindCore"], path: "Sources/macOS"),
        .target(name: "SecondWindPersistence", dependencies: ["SecondWindCore", "SecondWindMacOS"], path: "Sources/Persistence"),
        .executableTarget(name: "SecondWindUI", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindPersistence", "SecondWindMacOS"], path: "Sources/UI"),
        .testTarget(name: "SecondWindCoreTests", dependencies: ["SecondWindCore", "SecondWindApplication", "SecondWindPersistence", "SecondWindMacOS"], path: "Tests/SecondWindCoreTests")
    ]
)
