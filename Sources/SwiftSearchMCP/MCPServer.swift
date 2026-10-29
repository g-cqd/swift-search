internal import AemiJSON
internal import ReportSupport
public import SwiftSearch
public import SwiftSearchLSP
internal import Synchronization

/// What the server asks for a sourcekit-lsp session: a ``LanguageServerPool``, or a test's stand-in.
public protocol LanguageServerProvider: Sendable {
    func session(for workspace: String) async throws -> LanguageServerSession
}

/// A Model Context Protocol server: the search and the sourcekit-lsp queries as tools.
///
/// ``handle(_:)`` answers one JSON-RPC message; ``MCPStdio`` feeds it the lines of standard input. Requests may be
/// handled concurrently: the server keeps no state between them but the cancelled ids.
public final class MCPServer: Sendable {
    /// The protocol versions the server speaks, newest first. A client offering one of them gets it back; any other gets
    /// the newest.
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    /// The most results a tool returns.
    public static let maximumLimit = 2000

    /// The directory relative paths are resolved against, and the default search path.
    public let root: String
    let cacheRoot: String?
    let languageServers: (any LanguageServerProvider)?
    private let presenter: PathPresenter
    private let cancelled = Mutex<Set<String>>([])

    /// - Parameters:
    ///   - root: absolute; relative tool paths resolve against it and reported paths inside it are relative to it.
    ///   - cacheRoot: the facts cache and index database directory; nil for no facts cache.
    ///   - languageServers: the sourcekit-lsp sessions; nil leaves the `lsp_` tools unlisted.
    public init(
        root: String, cacheRoot: String? = Corpus.defaultCacheRoot, languageServers: (any LanguageServerProvider)?
    ) {
        self.root = root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
        self.cacheRoot = cacheRoot
        self.languageServers = languageServers
        self.presenter = PathPresenter(root: self.root)
    }

    /// The answer to one message, or nil for a notification, a response or a cancelled request.
    /// - Complexity: that of the tool called; O(*n*) in the message size otherwise.
    public func handle(_ line: [UInt8]) async -> [UInt8]? {
        guard let document = try? AemiJSON.parse(line) else {
            return Self.failure(id: .null, code: -32700, message: "parse error: not JSON")
        }
        let message = document.root
        guard message.isObject else {
            return Self.failure(id: .null, code: -32600, message: "invalid request: not an object")
        }
        let id = message["id"]
        guard let method = message["method"].string else { return nil }  // a response to us: we send no requests
        guard id.exists, !id.isNull else {
            if method == "notifications/cancelled", let raw = try? message["params"]["requestId"].encodedBytes() {
                cancelled.withLock { _ = $0.insert(String(decoding: raw, as: UTF8.self)) }
            }
            return nil
        }
        let idValue = JSONValue(id)
        let result: Result<JSONValue, MCPError>
        switch method {
        case "initialize": result = .success(initialize(message["params"]))
        case "ping": result = .success([:])
        case "tools/list": result = .success(["tools": tools])
        case "tools/call": result = await call(message["params"])
        default: result = .failure(MCPError(code: -32601, message: "method not found: \(method)"))
        }
        if let raw = try? id.encodedBytes(),
            cancelled.withLock({ $0.remove(String(decoding: raw, as: UTF8.self)) != nil })
        {
            return nil
        }
        switch result {
        case .success(let value): return Self.encode(["jsonrpc": "2.0", "id": idValue, "result": value])
        case .failure(let error): return Self.failure(id: idValue, code: error.code, message: error.message)
        }
    }

    // MARK: Methods

    private func initialize(_ params: JSON) -> JSONValue {
        let offered = params["protocolVersion"].string ?? ""
        let version = Self.protocolVersions.contains(offered) ? offered : Self.protocolVersions[0]
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(ToolInfo.name), "version": .string(ToolInfo.version)],
            "instructions": .string(
                "Search Swift code by symbol. search_symbols and find_usages read the sources (and the index store when "
                    + "asked); the lsp_ tools ask sourcekit-lsp, which may need the package to build first. Paths are "
                    + "relative to \(root) unless absolute."),
        ]
    }

    private var tools: JSONValue {
        guard case .array(let all) = ToolCatalog.tools else { return [] }
        guard languageServers == nil else { return .array(all) }
        return .array(
            all.filter { tool in
                guard case .object(let members) = tool, case .string(let name)? = members["name"] else { return true }
                return !name.hasPrefix("lsp_")
            })
    }

    private func call(_ params: JSON) async -> Result<JSONValue, MCPError> {
        guard let name = params["name"].string else {
            return .failure(MCPError(code: -32602, message: "invalid params: 'name' is required"))
        }
        let arguments = ToolArguments(json: params["arguments"])
        do {
            let text: [UInt8]
            switch name {
            case ToolCatalog.search: text = try await search(arguments)
            case ToolCatalog.usages: text = try await usages(arguments)
            case ToolCatalog.workspaceSymbols: text = try await workspaceSymbols(arguments)
            case let tool where ToolCatalog.positionTools.contains(tool): text = try await position(tool, arguments)
            default: return .failure(MCPError(code: -32602, message: "unknown tool: \(name)"))
            }
            return .success(Self.toolResult(text, isError: false))
        } catch let error as ArgumentError {
            return .success(Self.toolResult(Array(error.message.utf8), isError: true))
        } catch {
            return .success(Self.toolResult(Array(String(describing: error).utf8), isError: true))
        }
    }

    // MARK: Encoding

    static func toolResult(_ text: [UInt8], isError: Bool) -> JSONValue {
        [
            "content": [["type": "text", "text": .string(String(decoding: text, as: UTF8.self))]],
            "isError": .bool(isError),
        ]
    }

    static func encode(_ value: JSONValue) -> [UInt8] {
        // Every value here is built from strings, booleans and integers, which always encode.
        (try? value.encodedBytes())
            ?? Array(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"encoding"}}"#.utf8)
    }

    static func failure(id: JSONValue, code: Int, message: String) -> [UInt8] {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": .int(Int64(code)), "message": .string(message)]])
    }

    /// A path as the tools report it: relative inside the root, absolute outside.
    func present(_ path: String) -> String {
        presenter.path(path)
    }

    /// A tool's path argument, absolute.
    func resolve(_ path: String) -> String {
        path.hasPrefix("/") ? path : root + "/" + path
    }
}

/// A JSON-RPC error.
struct MCPError: Error, Sendable {
    let code: Int
    let message: String
}
