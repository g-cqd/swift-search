import Testing

@testable import SwiftSearch

@Suite struct SearchWorkspaceTests {
    private static let files = [
        "Sources/App/Client.swift": """
        public final class Client {
            public static let shared = Client()
            private var token: String?
            public func fetch(id: Int) -> String { "\\(id)" }
        }
        """,
        "Sources/App/Use.swift": """
        func run() {
            _ = Client.shared.fetch(id: 1)
        }
        """,
        "Sources/App/Notes.txt": "fetch",
    ]

    private func open(_ corpus: TemporaryCorpus, cacheRoot: String? = nil) async throws -> SearchWorkspace {
        try await SearchWorkspace.open(.init(paths: [corpus.root], cacheRoot: cacheRoot))
    }

    @Test func `finds declarations in the Swift files under a directory`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let workspace = try await open(corpus)
        #expect(workspace.corpus.files.count == 2)
        let matches = try workspace.find(SymbolQuery(pattern: .name("fetch")))
        #expect(matches.map(\.location) == [corpus.path("Sources/App/Client.swift") + ":4:17"])
    }

    @Test func `filters by kind, access level and enclosing type, then cuts at the limit after sorting`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let workspace = try await open(corpus)
        let regex = SymbolQuery.Pattern.regex(".*")
        #expect(try workspace.find(SymbolQuery(pattern: regex, kinds: [.method])).map(\.name) == ["fetch"])
        #expect(try workspace.find(SymbolQuery(pattern: regex, accessLevels: [.private])).map(\.name) == ["token"])
        #expect(try workspace.find(SymbolQuery(pattern: regex, containingType: "Client")).count == 3)
        #expect(try workspace.find(SymbolQuery(pattern: regex, limit: 2)).map(\.name) == ["Client", "shared"])
    }

    @Test func `reports the usages of a declaration`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let report = try await open(corpus).usages(
            of: SymbolQuery(pattern: .qualified(types: ["Client"], name: "fetch")))
        #expect(report.matches.count == 1)
        #expect(report.usages.map(\.location) == [corpus.path("Sources/App/Use.swift") + ":2:23"])
    }

    @Test func `refuses a USR without an index store`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let workspace = try await open(corpus)
        #expect(throws: SearchError.usrNeedsIndexStore("s:3App6ClientC")) {
            try workspace.find(SymbolQuery(pattern: .usr("s:3App6ClientC")))
        }
    }

    @Test func `refuses a missing path and a directory without Swift files`() async throws {
        let corpus = try TemporaryCorpus(["notes.txt": "x"])
        defer { corpus.remove() }
        await #expect(throws: SearchError.pathNotFound(corpus.path("missing"))) {
            try await SearchWorkspace.open(.init(paths: [corpus.path("missing")], cacheRoot: nil))
        }
        await #expect(throws: SearchError.noSwiftFiles([corpus.root])) {
            try await SearchWorkspace.open(.init(paths: [corpus.root], cacheRoot: nil))
        }
    }

    @Test func `leaves out the paths an exclusion names`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let workspace = try await SearchWorkspace.open(
            .init(paths: [corpus.root], exclude: ["Use.swift"], cacheRoot: nil))
        #expect(workspace.corpus.files == [corpus.path("Sources/App/Client.swift")])
    }

    @Test func `reuses the facts of unchanged files from the cache`() async throws {
        let corpus = try TemporaryCorpus(Self.files)
        defer { corpus.remove() }
        let cacheRoot = corpus.path("cache")
        let first = try await open(corpus, cacheRoot: cacheRoot)
        let second = try await open(corpus, cacheRoot: cacheRoot)
        #expect(first.corpus.cacheHits == 0)
        #expect(second.corpus.cacheHits == 2)
        #expect(
            try second.find(SymbolQuery(pattern: .name("fetch"))) == first.find(SymbolQuery(pattern: .name("fetch"))))
    }
}
