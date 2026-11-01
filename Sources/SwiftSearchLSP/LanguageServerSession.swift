internal import AemiJSON
internal import Foundation
internal import SourceCorpus
internal import Synchronization

/// The questions swift-search asks sourcekit-lsp, in swift-search's positions: 1-based lines, 1-based UTF-8 columns.
///
/// A file a position names is opened in the server (`textDocument/didOpen`) the first time, so the server answers from
/// the bytes on disk, and stays open for the session.
public final class LanguageServerSession: Sendable {
    public let connection: LanguageServerConnection
    public let workspace: String
    private struct Documents {
        var positions: [String: TextPositions] = [:]
        var opened: Set<String> = []
    }
    private let documents = Mutex(Documents())
    /// Whether the server agreed to UTF-8 positions; UTF-16 otherwise (the protocol's default).
    private let utf8Positions = Atomic(false)

    public init(connection: LanguageServerConnection, workspace: String) {
        self.connection = connection
        self.workspace = workspace
    }

    // MARK: Lifecycle

    /// `initialize`, then `initialized`.
    public func initialize() async throws {
        let root = Self.uri(workspace)
        let result = try await connection.request(
            "initialize",
            [
                "processId": .int(Int64(ProcessInfo.processInfo.processIdentifier)),
                "rootUri": .string(root),
                "workspaceFolders": [
                    ["uri": .string(root), "name": .string(URL(filePath: workspace).lastPathComponent)]
                ],
                "capabilities": [
                    "general": ["positionEncodings": ["utf-8", "utf-16"]],
                    "textDocument": [
                        "hover": ["contentFormat": ["plaintext", "markdown"]],
                        "definition": ["linkSupport": false],
                        "callHierarchy": [:],
                    ],
                    "workspace": ["symbol": [:]],
                ],
            ], timeout: .seconds(60))
        utf8Positions.store(result["capabilities"]["positionEncoding"].string == "utf-8", ordering: .relaxed)
        try await connection.notify("initialized", [:])
    }

    /// `shutdown`, then `exit`; errors are dropped, the server is being stopped anyway.
    public func shutdown() async {
        _ = try? await connection.request("shutdown", .null, timeout: .seconds(10))
        try? await connection.notify("exit", .null)
    }

    /// How long an index-backed query waits for sourcekit-lsp's background index to catch up with the sources.
    public static let indexTimeout: Duration = .seconds(600)

    /// `workspace/synchronize` with `index`: returns once the background index is up to date with the sources, so a
    /// query answered from the index sees every file. A server too old to know the request is not waited for.
    public func synchronizeIndex(timeout: Duration = indexTimeout) async throws {
        do {
            _ = try await connection.request("workspace/synchronize", ["index": true], timeout: timeout)
        } catch LanguageServerError.response(let code, _) where code == -32601 {
            return  // method not found: an older sourcekit-lsp
        }
    }

    // MARK: Queries

    /// `workspace/symbol`: the symbols whose names the server matches against `query` (its own fuzzy match), once the
    /// index is up to date.
    public func workspaceSymbols(_ query: String) async throws -> [LanguageServerSymbol] {
        try await synchronizeIndex()
        let result = try await connection.request("workspace/symbol", ["query": .string(query)])
        return result.arrayValue.compactMap { item in
            let location = item["location"]
            guard let position = position(uri: location["uri"], at: location["range"]["start"]) else { return nil }
            return LanguageServerSymbol(
                name: item["name"].stringValue, kind: SymbolKindName.name(item["kind"].intValue),
                container: item["containerName"].string, position: position, detail: nil)
        }
    }

    /// `textDocument/definition`: where the symbol at `position` is declared.
    public func definition(at position: SourcePosition) async throws -> [SourcePosition] {
        try await locations("textDocument/definition", at: position)
    }

    /// `textDocument/implementation`: the conformances and overrides of the requirement or member at `position`, once
    /// the index is up to date.
    public func implementations(at position: SourcePosition) async throws -> [SourcePosition] {
        try await synchronizeIndex()
        return try await locations("textDocument/implementation", at: position)
    }

    /// `textDocument/references`: every use of the symbol at `position`, its declaration when asked, once the index is
    /// up to date.
    public func references(at position: SourcePosition, includeDeclaration: Bool = false) async throws
        -> [SourcePosition]
    {
        try await synchronizeIndex()
        return try await locations(
            "textDocument/references", at: position,
            extra: ["context": ["includeDeclaration": .bool(includeDeclaration)]])
    }

    /// Whether sourcekit-lsp's index holds the symbol at `position`: an indexed symbol has at least its declaration
    /// among its references. An empty answer from the index (references, implementations, callers, callees) about a
    /// symbol it holds no record of says nothing about the symbol's uses.
    public func indexHasRecord(at position: SourcePosition) async throws -> Bool {
        !(try await references(at: position, includeDeclaration: true)).isEmpty
    }

    /// The note for an empty answer about a symbol the index holds no record of.
    public static func unindexedNote(_ position: SourcePosition) -> String {
        "sourcekit-lsp's index holds no record of the symbol at \(position.file):\(position.line):\(position.column), "
            + "so the empty answer says nothing about its uses. Its background index leaves out a file outside every "
            + "target, and a whole package SwiftPM cannot load, as when a build-tool plugin does not build (an "
            + "Xcode-only one, for example). The syntax (usages) or a build's index store (usages --index-store-path) "
            + "still answer."
    }

    /// `textDocument/hover`: the declaration and documentation of the symbol at `position`, as text.
    public func hover(at position: SourcePosition) async throws -> String? {
        let result = try await connection.request("textDocument/hover", try await documentPosition(position))
        let contents = result["contents"]
        if let text = contents.string { return text }
        if let text = contents["value"].string { return text }
        let parts = contents.arrayValue.compactMap { $0.string ?? $0["value"].string }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// `callHierarchy/incomingCalls`: the functions that call the one at `position`, and where, once the index is up to
    /// date.
    public func callers(of position: SourcePosition) async throws -> [LanguageServerCall] {
        try await calls("callHierarchy/incomingCalls", end: "from", of: position)
    }

    /// `callHierarchy/outgoingCalls`: the functions the one at `position` calls, and where, once the index is up to
    /// date.
    public func callees(of position: SourcePosition) async throws -> [LanguageServerCall] {
        try await calls("callHierarchy/outgoingCalls", end: "to", of: position)
    }

    // MARK: Plumbing

    private func locations(_ method: String, at position: SourcePosition, extra: [String: JSONValue] = [:])
        async throws -> [SourcePosition]
    {
        var params = try await documentPosition(position)
        if case .object(var members) = params {
            for (key, value) in extra { members[key] = value }
            params = .object(members)
        }
        let result = try await connection.request(method, params)
        // A Location, a Location[], or a LocationLink[] (`targetUri`, `targetSelectionRange`).
        let items = result.isArray ? result.arrayValue : (result.isObject ? [result] : [])
        var seen: Set<SourcePosition> = []
        return items.compactMap { item -> SourcePosition? in
            let found =
                item["uri"].exists
                ? self.position(uri: item["uri"], at: item["range"]["start"])
                : self.position(uri: item["targetUri"], at: item["targetSelectionRange"]["start"])
            guard let found, seen.insert(found).inserted else { return nil }
            return found
        }
    }

    private func calls(_ method: String, end: String, of position: SourcePosition) async throws
        -> [LanguageServerCall]
    {
        try await synchronizeIndex()
        let prepared = try await connection.request(
            "textDocument/prepareCallHierarchy", try await documentPosition(position))
        guard let item = prepared.arrayValue.first, let raw = try? item.encodedBytes(),
            let value = try? AemiJSON.parse(raw)
        else { return [] }
        let result = try await connection.request(method, ["item": JSONValue(value.root)])
        return result.arrayValue.compactMap { call in
            let other = call[end]
            guard let symbol = symbol(other) else { return nil }
            // `fromRanges` are in the caller's file: the item's for incoming calls, the prepared one's for outgoing.
            let callerURI = end == "from" ? other["uri"] : item["uri"]
            let sites = call["fromRanges"].arrayValue.compactMap { self.position(uri: callerURI, at: $0["start"]) }
            return LanguageServerCall(symbol: symbol, callSites: sites)
        }
    }

    private func symbol(_ item: JSON) -> LanguageServerSymbol? {
        guard let position = position(uri: item["uri"], at: item["selectionRange"]["start"]) else { return nil }
        return LanguageServerSymbol(
            name: item["name"].stringValue, kind: SymbolKindName.name(item["kind"].intValue), container: nil,
            position: position, detail: item["detail"].string)
    }

    /// `{textDocument, position}` for `position`, opening its file first.
    private func documentPosition(_ position: SourcePosition) async throws -> JSONValue {
        let file = SourcePath.canonical(position.file)
        let positions = try await open(file)
        let utf16 = !utf8Positions.load(ordering: .relaxed)
        return [
            "textDocument": ["uri": .string(Self.uri(file))],
            "position": [
                "line": .int(Int64(max(position.line - 1, 0))),
                "character": .int(
                    Int64(positions.character(line: position.line, column: position.column, utf16: utf16))),
            ],
        ]
    }

    /// Reads `file` and sends `textDocument/didOpen` the first time.
    private func open(_ file: String) async throws -> TextPositions {
        if let known = documents.withLock({ $0.positions[file] }) { return known }
        guard let bytes = try? BoundedFileReader.read(path: file, cap: BoundedFileReader.sourceByteCap) else {
            throw LanguageServerError.unreadableFile(file)
        }
        let text = String(decoding: bytes, as: UTF8.self)
        let positions = TextPositions(bytes: bytes)
        let first = documents.withLock { documents in
            documents.positions[file] = positions
            return documents.opened.insert(file).inserted
        }
        if first {
            try await connection.notify(
                "textDocument/didOpen",
                [
                    "textDocument": [
                        "uri": .string(Self.uri(file)), "languageId": "swift", "version": 1, "text": .string(text),
                    ]
                ])
        }
        return positions
    }

    /// A ``SourcePosition`` for an LSP `uri` and `{line, character}`; nil when either is missing.
    private func position(uri: JSON, at start: JSON) -> SourcePosition? {
        guard let text = uri.string, let url = URL(string: text), url.isFileURL, let line = start["line"].int,
            let character = start["character"].int
        else { return nil }
        let file = SourcePath.canonical(url.path)
        let positions =
            documents.withLock { $0.positions[file] }
            ?? {
                guard let bytes = try? BoundedFileReader.read(path: file, cap: BoundedFileReader.sourceByteCap) else {
                    return nil
                }
                let positions = TextPositions(bytes: bytes)
                documents.withLock { $0.positions[file] = positions }
                return positions
            }()
        let utf16 = !utf8Positions.load(ordering: .relaxed)
        let column =
            positions?.column(line: line, character: character, utf16: utf16) ?? (max(character, 0) + 1)
        return SourcePosition(file: file, line: line + 1, column: column)
    }

    static func uri(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }
}
