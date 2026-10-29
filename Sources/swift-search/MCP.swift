internal import AnalyzerCLI
internal import ArgumentParser
internal import SourceCorpus
internal import SwiftSearch
internal import SwiftSearchMCP

/// `swift-search mcp`: the Model Context Protocol server on standard input and output.
struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Serve the search and sourcekit-lsp as MCP tools over standard input and output.",
        discussion: """
            Tools: search_symbols, find_usages, and with sourcekit-lsp lsp_workspace_symbols, lsp_definition, \
            lsp_references, lsp_implementations, lsp_hover, lsp_callers and lsp_callees. One sourcekit-lsp runs per \
            workspace, started on first use and stopped when the input ends.
            """)

    @Option(
        help: ArgumentHelp(
            "The directory tool paths are relative to (default: the current one).",
            valueName: "directory"))
    var root: String = "."

    @Flag(name: .customLong("no-lsp"), help: "Do not offer the sourcekit-lsp tools.")
    var noLanguageServer = false

    @Option(name: .customLong("sourcekit-lsp"), help: ArgumentHelp("A sourcekit-lsp to run.", valueName: "path"))
    var sourceKitLSP: String?

    @OptionGroup(title: OptionGroupTitle.cache) var cache: CacheOptions

    func run() async throws {
        let pool = noLanguageServer ? nil : LanguageServerPool(executable: sourceKitLSP)
        let server = MCPServer(
            root: SourcePath.absolute(root),
            cacheRoot: cache.noCache ? nil : (cache.cachePath ?? Corpus.defaultCacheRoot), languageServers: pool)
        await MCPStdio.serveStandardStreams(server, pool: pool)
    }
}
