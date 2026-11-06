// swift-tools-version: 6.4
import PackageDescription

// Strict-by-default, as in the analyzer family: warnings are errors, upcoming features are on, and strict memory
// safety keeps the unsafe surface at zero. Swift 6 language mode includes complete strict concurrency.
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
    // macOS 15: analyzerkit's floor, and the stdlib Synchronization module (Mutex).
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
        // The project model, source discovery, bounded reads, index-store sessions and CLI surface of the family.
        .package(
            url: "https://github.com/g-cqd/analyzerkit.git", revision: "a7814db1cdf56fbc97460f37e469a194e31cfc12"),
        // Bounded concurrency (AemiRuntime). The revision analyzerkit pins: one revision per package in a graph.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "409c647a91736065ac53c1877abe2cf4840f7617"),
        // The JSON of the MCP and LSP wires and of `--format json`.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "8b7bfe373d2b36dbfe8e7ec068478b1aea65b12a"),
        // Linear-time regular expressions: a query pattern is attacker input over MCP, and no pattern can make a search
        // exponential. The revision AemiJSON resolves.
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "2d4cf1203dac2c992db9d3ab4da3756968d73d9e"),
        // The sourcekit-lsp child process: a session of its own, torn down with its descendants.
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.2", traits: []),
        // FileDescriptor off Apple platforms, where the System framework is not there.
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
        // IndexStoreDB, on macOS only; the revision analyzerkit pins.
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git", revision: "0390867818c28241af4650eb4ef29af5669335a3"),
    ],
    targets: [
        // Symbol search over Swift sources: the query language, the syntax and index-store resolvers, usages and
        // context.
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
        // A client of the toolchain's sourcekit-lsp: definitions, references, call and type hierarchy, hover.
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
        // The Model Context Protocol server: the search and the language-server queries as tools, over stdio.
        .target(
            name: "SwiftSearchMCP",
            dependencies: [
                "SwiftSearch", "SwiftSearchLSP",
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "ProjectModel", package: "analyzerkit"),
                .product(name: "ReportSupport", package: "analyzerkit"),
                // Blocking reads of standard input, off the cooperative pool.
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
