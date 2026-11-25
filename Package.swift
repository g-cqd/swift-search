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
            url: "https://github.com/g-cqd/analyzerkit.git", revision: "3b5d779d61e51a346fcb86c69ac3ab8ebcbdd6c0"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "bd5e4cf4441ca3ed1b424935142586ccaac0f835"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "1c098f0456a2f86dee32dfd9b85455980216589f"),
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "2df69da6f7b8086ae07272d4368d45fe1fd57160"),
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
