// swift-tools-version: 6.4
import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]

let package = Package(
    name: "swift-search",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SwiftSearch", targets: ["SwiftSearch"]),
        .library(name: "SwiftSearchLSP", targets: ["SwiftSearchLSP"]),
        .library(name: "SwiftSearchMCP", targets: ["SwiftSearchMCP"]),
        .executable(name: "swift-search", targets: ["swift-search"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(
            url: "https://github.com/g-cqd/analyzerkit.git", revision: "2e54cc659fab831ff3294c00b6e013fca15d45d8"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "9e38d1bee60d5d65acffef4538c671b49860c6af"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "9144b71be7714e15db293197b47edcc55ffde71b"),
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "ae05021fde62d5c775f2cf77af4905670cab300d"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.2", traits: []),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git", revision: "0390867818c28241af4650eb4ef29af5669335a3"),
    ],
    targets: [
        .target(
            name: "SwiftSearch",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SourceCorpus", package: "analyzerkit"),
                .product(name: "CorpusScan", package: "analyzerkit"),
                .product(name: "ProjectModel", package: "analyzerkit"),
                .product(name: "IndexStoreSupport", package: "analyzerkit"),
                .product(name: "ReportSupport", package: "analyzerkit"),
                .product(name: "AemiRegex", package: "AemiRegex"),
                .product(name: "IndexStoreDB", package: "indexstore-db", condition: .when(platforms: [.macOS])),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "SwiftSearchLSP",
            dependencies: [
                "SwiftSearch",
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "IndexStoreSupport", package: "analyzerkit"),
                .product(name: "SourceCorpus", package: "analyzerkit"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "SwiftSearchMCP",
            dependencies: [
                "SwiftSearch", "SwiftSearchLSP",
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "ProjectModel", package: "analyzerkit"),
                .product(name: "ReportSupport", package: "analyzerkit"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "swift-search",
            dependencies: [
                "SwiftSearch", "SwiftSearchLSP", "SwiftSearchMCP",
                .product(name: "AnalyzerCLI", package: "analyzerkit"),
                .product(name: "ProjectModel", package: "analyzerkit"),
                .product(name: "ReportSupport", package: "analyzerkit"),
                .product(name: "SourceCorpus", package: "analyzerkit"),
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SwiftSearchTests",
            dependencies: ["SwiftSearch", .product(name: "ReportSupport", package: "analyzerkit")],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SwiftSearchLSPTests",
            dependencies: [
                "SwiftSearchLSP", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "IndexStoreSupport", package: "analyzerkit"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SwiftSearchMCPTests",
            dependencies: [
                "SwiftSearchMCP", "SwiftSearch", "SwiftSearchLSP", .product(name: "AemiJSON", package: "AemiJSON"),
            ],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
