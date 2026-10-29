import Foundation
import ReportSupport
import Testing

@testable import SwiftSearch

/// The compiler used to build real index stores: fixtures are stores `swiftc -index-store-path` wrote, never mocks.
private enum Compiler {
    static let swiftc: String? = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "swiftc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !path.isEmpty ? path : nil
    }()

    /// Builds `files` of `corpus` as module `App`, writing an index store at `store`.
    static func index(_ corpus: TemporaryCorpus, files: [String], store: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(swiftc))
        process.arguments =
            ["-emit-library", "-module-name", "App", "-index-store-path", store, "-o", corpus.path("libApp.dylib")]
            + files.map(corpus.path)
        process.currentDirectoryURL = URL(fileURLWithPath: corpus.root)
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}

@Suite(.enabled(if: Compiler.swiftc != nil, "needs swiftc to build an index store (macOS with Xcode or the CLT)"))
struct IndexStoreTests {
    private static let files = [
        "Sources/App/Client.swift": """
        public final class Client {
            public static let shared = Client()
            public func fetch(id: Int) -> String { "\\(id)" }
        }
        public final class Other {
            public func fetch(id: Int) -> String { "" }
        }
        """,
        "Sources/App/Use.swift": """
        func run(other: Other) {
            _ = Client.shared.fetch(id: 1)
            _ = other.fetch(id: 2)
        }
        """,
    ]

    private func workspace() async throws -> (TemporaryCorpus, SearchWorkspace) {
        let corpus = try TemporaryCorpus(Self.files)
        let store = corpus.path("store")
        try Compiler.index(corpus, files: Array(Self.files.keys).sorted(), store: store)
        let workspace = try await SearchWorkspace.open(
            .init(paths: [corpus.path("Sources")], cacheRoot: corpus.path("cache"), indexStore: .path(store)))
        return (corpus, workspace)
    }

    @Test func `gives each syntax match the USR and module the index records`() async throws {
        let (corpus, workspace) = try await workspace()
        defer { corpus.remove() }
        #expect(workspace.hasIndexStore)
        let match = try #require(
            try workspace.find(SymbolQuery(pattern: .qualified(types: ["Client"], name: "fetch"))).first)
        #expect(match.usr?.hasPrefix("s:3App6ClientC5fetch") == true)
        #expect(match.module == "App")
        #expect(match.source == .syntax)
    }

    @Test func `resolves a USR`() async throws {
        let (corpus, workspace) = try await workspace()
        defer { corpus.remove() }
        let usr = try #require(try workspace.find(SymbolQuery(pattern: .name("Client"))).first?.usr)
        let byUSR = try workspace.find(SymbolQuery(pattern: .usr(usr)))
        #expect(byUSR.map(\.name) == ["Client"])
        #expect(byUSR.first?.usr == usr)
    }

    @Test func `reports only the uses the compiler resolved to the declaration`() async throws {
        let (corpus, workspace) = try await workspace()
        defer { corpus.remove() }
        let report = try workspace.usages(of: SymbolQuery(pattern: .qualified(types: ["Client"], name: "fetch")))
        #expect(report.usages.map(\.location) == [corpus.path("Sources/App/Use.swift") + ":2:23"])
        #expect(report.usages.allSatisfy { $0.isResolved })
    }

    @Test func `falls back to the syntax in a file changed since the build`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let store = corpus.path("store")
        try Compiler.index(corpus, files: Array(Self.files.keys).sorted(), store: store)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: corpus.path("Sources/App/Use.swift"))
        let workspace = try await SearchWorkspace.open(
            .init(paths: [corpus.path("Sources")], cacheRoot: corpus.path("cache"), indexStore: .path(store)))
        let report = try workspace.usages(of: SymbolQuery(pattern: .qualified(types: ["Client"], name: "fetch")))
        // Both `fetch` calls go through an expression base, so the syntax cannot tell them apart.
        #expect(report.usages.map(\.line) == [2, 3])
        #expect(report.usages.allSatisfy { !$0.isResolved })
        #expect(workspace.notes.contains { $0.code == "index-changed-since-build" })
    }
}
