internal import AemiJSON
internal import ProjectModel
internal import ReportSupport
internal import SwiftSearch
internal import SwiftSearchLSP

extension MCPServer {
    /// What a search tool returns.
    private struct SearchOutput: Encodable {
        let matches: [MatchRecord]
        let truncated: Bool
        let notes: [String]
    }

    private struct UsagesOutput: Encodable {
        let matches: [MatchRecord]
        let usages: [UsageRecord]
        let truncated: Bool
        let notes: [String]
    }

    private struct PositionOutput: Encodable {
        let symbol: String
        let locations: [String]?
        let calls: [CallRecord]?
        let hover: String?
        var notes: [String]? = nil
    }

    private struct CallRecord: Encodable {
        let symbol: String
        let kind: String
        let location: String
        let callSites: [String]
    }

    private struct SymbolRecord: Encodable {
        let name: String
        let kind: String
        let container: String?
        let location: String
    }

    // MARK: search_symbols, find_usages

    func search(_ arguments: ToolArguments) async throws -> [UInt8] {
        let (workspace, query, limit) = try await prepare(arguments)
        let all = try workspace.find(query)
        let contextLines = try arguments.integer("context_lines", in: 0...SymbolContextOptions.maximumContextLines) ?? 0
        let options = SymbolContextOptions(
            linesBefore: contextLines, linesAfter: contextLines, signature: try arguments.bool("signature") ?? false,
            body: try arguments.bool("body") ?? false, documentation: try arguments.bool("documentation") ?? false,
            scope: try arguments.bool("scope") ?? false)
        var records: [MatchRecord] = []
        for match in all.prefix(limit) {
            let context =
                options.isEmpty
                ? nil
                : await SymbolContextExtractor.context(
                    file: match.file, line: match.line, column: match.column, options: options)
            records.append(MatchRecord(match, path: present, context: context))
        }
        return try Self.json(
            SearchOutput(matches: records, truncated: all.count > limit, notes: workspace.notes.map(\.message)))
    }

    func usages(_ arguments: ToolArguments) async throws -> [UInt8] {
        let (workspace, query, limit) = try await prepare(arguments)
        let report = try workspace.usages(of: query)
        return try Self.json(
            UsagesOutput(
                matches: report.matches.map { MatchRecord($0, path: present) },
                usages: report.usages.prefix(limit).map { UsageRecord($0, path: present) },
                truncated: report.usages.count > limit, notes: workspace.notes.map(\.message)))
    }

    /// The workspace and query a search tool's arguments describe, and its limit.
    private func prepare(_ arguments: ToolArguments) async throws -> (SearchWorkspace, SymbolQuery, Int) {
        let text = try arguments.requiredString("query")
        let pattern: SymbolQuery.Pattern
        do {
            pattern = try QueryParser.parse(text)
        } catch {
            throw ArgumentError(message: error.description)
        }
        let limit = try arguments.integer("limit", in: 1...Self.maximumLimit) ?? 100
        let query = SymbolQuery(
            pattern: pattern, kinds: try arguments.values("kind", of: DeclarationKind.self),
            accessLevels: try arguments.values("access", of: AccessLevel.self),
            containingType: try arguments.string("in_type"))
        let paths = try arguments.strings("paths").map(resolve)
        let indexPath = try arguments.string("index_store_path").map(resolve)
        let wantsIndex = try arguments.bool("index_store") ?? false
        let index: SearchWorkspace.IndexStoreRequest = indexPath.map { .path($0) } ?? (wantsIndex ? .discover : .none)
        let workspace = try await SearchWorkspace.open(
            .init(
                paths: paths.isEmpty ? [root] : paths, exclude: try arguments.strings("exclude"), cacheRoot: cacheRoot,
                indexStore: index))
        return (workspace, query, limit)
    }

    // MARK: lsp_ tools

    func workspaceSymbols(_ arguments: ToolArguments) async throws -> [UInt8] {
        let query = try arguments.requiredString("query")
        let session = try await languageServer(for: try arguments.string("workspace").map(resolve) ?? root)
        let symbols = try await session.workspaceSymbols(query)
        return try Self.json(
            symbols.prefix(Self.maximumLimit).map {
                SymbolRecord(
                    name: $0.name, kind: $0.kind, container: $0.container,
                    location: "\(present($0.position.file)):\($0.position.line):\($0.position.column)")
            })
    }

    func position(_ tool: String, _ arguments: ToolArguments) async throws -> [UInt8] {
        let (position, symbol) = try await target(arguments)
        let workspace =
            try arguments.string("workspace").map(resolve)
            ?? ProjectLayout.discover(paths: [position.file])?.root ?? root
        let session = try await languageServer(for: workspace)
        let format = { (found: SourcePosition) in "\(self.present(found.file)):\(found.line):\(found.column)" }
        var output: PositionOutput
        switch tool {
        case ToolCatalog.definition:
            output = .init(
                symbol: symbol, locations: try await session.definition(at: position).map(format), calls: nil,
                hover: nil)
        case ToolCatalog.references:
            output = .init(
                symbol: symbol,
                locations: try await session.references(at: position).prefix(Self.maximumLimit).map(format), calls: nil,
                hover: nil)
        case ToolCatalog.implementations:
            output = .init(
                symbol: symbol, locations: try await session.implementations(at: position).map(format), calls: nil,
                hover: nil)
        case ToolCatalog.hover:
            output = .init(symbol: symbol, locations: nil, calls: nil, hover: try await session.hover(at: position))
        default:
            let calls =
                tool == ToolCatalog.callers
                ? try await session.callers(of: position) : try await session.callees(of: position)
            output = .init(
                symbol: symbol, locations: nil,
                calls: calls.prefix(Self.maximumLimit).map {
                    CallRecord(
                        symbol: $0.symbol.name, kind: $0.symbol.kind, location: format($0.symbol.position),
                        callSites: $0.callSites.map(format))
                }, hover: nil)
        }
        let readsIndex = tool != ToolCatalog.definition && tool != ToolCatalog.hover
        if readsIndex, output.locations?.isEmpty ?? true, output.calls?.isEmpty ?? true,
            try await !session.indexHasRecord(at: position)
        {
            output.notes = [LanguageServerSession.unindexedNote(position)]
        }
        return try Self.json(output)
    }

    /// The position a position tool's arguments name: `file`, `line`, `column`, or a `symbol` query that names exactly
    /// one declaration.
    private func target(_ arguments: ToolArguments) async throws -> (SourcePosition, String) {
        if let symbol = try arguments.string("symbol") {
            let pattern: SymbolQuery.Pattern
            do {
                pattern = try QueryParser.parse(symbol)
            } catch {
                throw ArgumentError(message: error.description)
            }
            let workspace = try await SearchWorkspace.open(.init(paths: [root], cacheRoot: cacheRoot))
            let matches = try workspace.find(SymbolQuery(pattern: pattern))
            guard matches.count == 1, let match = matches.first else {
                let candidates = matches.prefix(20).map { "\($0.qualifiedSelector) at \(present($0.file)):\($0.line)" }
                throw ArgumentError(
                    message: matches.isEmpty
                        ? "no declaration matches '\(symbol)'"
                        : "'\(symbol)' names \(matches.count) declarations; give a qualified name, a selector, or "
                            + "file/line/column: " + candidates.joined(separator: "; "))
            }
            return (SourcePosition(file: match.file, line: match.line, column: match.column), match.qualifiedSelector)
        }
        let file = resolve(try arguments.requiredString("file"))
        guard let line = try arguments.integer("line", in: 1...10_000_000),
            let column = try arguments.integer("column", in: 1...1_000_000)
        else { throw ArgumentError(message: "give 'file', 'line' and 'column', or 'symbol'") }
        let position = SourcePosition(file: file, line: line, column: column)
        return (position, "\(present(file)):\(line):\(column)")
    }

    private func languageServer(for workspace: String) async throws -> LanguageServerSession {
        guard let languageServers else { throw ArgumentError(message: "this server runs without sourcekit-lsp") }
        return try await languageServers.session(for: workspace)
    }

    static func json(_ value: some Encodable) throws -> [UInt8] {
        try AemiJSON.JSONEncoder().encodeToBytes(value)
    }
}
