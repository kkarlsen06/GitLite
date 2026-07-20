// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Kvist",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Kvist", targets: ["Kvist"]),
        .executable(name: "KvistBenchmark", targets: ["KvistBenchmark"]),
        .executable(
            name: "KvistInteractionBenchmark",
            targets: ["KvistInteractionBenchmark"]
        ),
        .executable(
            name: "KvistHistoryBenchmark",
            targets: ["KvistHistoryBenchmark"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Kvist",
            path: "Sources/Kvist",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "KvistBenchmark",
            dependencies: ["KvistBenchmarkSupport"],
            path: "Sources/KvistBenchmark"
        ),
        .executableTarget(
            name: "KvistInteractionBenchmark",
            dependencies: ["KvistBenchmarkSupport"],
            path: "Sources/KvistInteractionBenchmark"
        ),
        .executableTarget(
            name: "KvistHistoryBenchmark",
            dependencies: ["KvistBenchmarkSupport"],
            path: "Sources/KvistHistoryBenchmark"
        ),
        .target(
            name: "KvistBenchmarkSupport",
            path: "Sources/KvistBenchmarkSupport"
        ),
        .testTarget(
            name: "KvistTests",
            dependencies: ["Kvist"],
            path: "Tests/KvistTests"
        ),
        .testTarget(
            name: "KvistBenchmarkTests",
            dependencies: ["KvistBenchmarkSupport"],
            path: "Tests/KvistBenchmarkTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
