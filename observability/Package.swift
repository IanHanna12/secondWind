// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecondWindObservability",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SecondWindObservability", targets: ["LocalObservability"]),
        .executable(name: "secondwind-observability", targets: ["LocalObservabilityCLI"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .target(
            name: "LocalObservability",
            dependencies: [
                .product(name: "SecondWindCore", package: "SecondWind"),
                .product(name: "SecondWindApplication", package: "SecondWind"),
                .product(name: "SecondWindPersistence", package: "SecondWind")
            ],
            path: "Sources/LocalObservability"
        ),
        .executableTarget(
            name: "LocalObservabilityCLI",
            dependencies: ["LocalObservability"],
            path: "Sources/LocalObservabilityCLI"
        ),
        .testTarget(
            name: "LocalObservabilityTests",
            dependencies: ["LocalObservability"],
            path: "Tests/LocalObservabilityTests"
        )
    ]
)
