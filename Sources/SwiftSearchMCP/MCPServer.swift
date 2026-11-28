internal import AemiJSON
internal import AemiJSONRPC
internal import AemiMCP
internal import ReportSupport
public import SwiftSearch
public import SwiftSearchLSP

/// What the server asks for a sourcekit-lsp session: a ``LanguageServerPool``, or a test's stand-in.
public protocol LanguageServerProvider: Sendable {
    func session(for workspace: String) async throws -> LanguageServerSession
}

/// A Model Context Protocol server: the search and the sourcekit-lsp queries as tools.
///
/// ``handle(_:)`` answers one JSON-RPC message; ``MCPStdio`` feeds it the lines of standard input. The protocol (version
/// negotiation, cancellation, JSON-RPC errors) is AemiMCP's; this type owns the tools. Requests may be handled
/// concurrently: a cancelled request's task is cancelled and it gets no answer.
public final class MCPServer: Sendable {
    /// The protocol versions the server speaks, newest first. A client offering one of them gets it back; any other gets
    /// the newest.
    public static let protocolVersions = MCPProtocolVersion.supported
    /// The most results a tool returns.
    public static let maximumLimit = SearchTools.maximumLimit

    /// The directory relative paths are resolved against, and the default search path.
    public let root: String
    private let protocolServer: AemiMCP.MCPServer

    /// - Parameters:
    ///   - root: absolute; relative tool paths resolve against it and reported paths inside it are relative to it.
    ///   - cacheRoot: the facts cache and index database directory; nil for no facts cache.
    ///   - languageServers: the sourcekit-lsp sessions; nil leaves the `lsp_` tools unlisted.
    public init(
        root: String, cacheRoot: String? = Corpus.defaultCacheRoot, languageServers: (any LanguageServerProvider)?
    ) {
        let root = root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
        let searchTools = SearchTools(root: root, cacheRoot: cacheRoot, languageServers: languageServers)
        let listed = ToolCatalog.tools.filter { languageServers != nil || !$0.name.hasPrefix("lsp_") }
        self.root = root
        protocolServer = AemiMCP.MCPServer(
            configuration: MCPServerConfiguration(
                name: ToolInfo.name,
                version: ToolInfo.version,
                instructions:
                    "Search Swift code by symbol. search_symbols and find_usages read the sources (and the index "
                    + "store when asked); the lsp_ tools ask sourcekit-lsp, which may need the package to build first. "
                    + "Paths are relative to \(root) unless absolute."
            ),
            tools: listed,
            callTool: { name, arguments in try await searchTools.call(name, ToolArguments(json: arguments.json)) }
        )
    }

    /// The answer to one message, or nil for a notification, a response or a cancelled request.
    /// - Complexity: that of the tool called; O(*n*) in the message size otherwise.
    public func handle(_ line: [UInt8]) async -> [UInt8]? {
        await protocolServer.handle(line)
    }

    /// The server AemiMCP's stdio runner serves.
    var protocolHandler: AemiMCP.MCPServer { protocolServer }
}
