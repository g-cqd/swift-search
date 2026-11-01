internal import AnalyzerCLI
internal import ArgumentParser
internal import Foundation
internal import ProjectModel
internal import SourceCorpus
internal import SwiftSearch
internal import SwiftSearchLSP

/// `swift-search lsp`: questions for the toolchain's sourcekit-lsp.
struct LSP: AsyncParsableCommand {
    enum Operation: String, CaseIterable, ExpressibleByArgument {
        case definition, references, implementations, hover, callers, callees, symbols
    }

    static let configuration = CommandConfiguration(
        abstract: "Ask the toolchain's sourcekit-lsp about a symbol.",
        discussion: """
            The target is file:line:column (1-based, UTF-8 column) or a query that names exactly one declaration \
            (Client.fetch(id:)); for `symbols`, the text sourcekit-lsp matches. sourcekit-lsp answers references, \
            callers and symbols from its index, which it builds in the background on its first run in a package.
            """)

    @Argument(help: "definition, references, implementations, hover, callers, callees or symbols.")
    var operation: Operation

    @Argument(help: "file:line:column, a query naming one declaration, or (symbols) the text to match.")
    var target: String

    @Option(
        help: ArgumentHelp(
            "The directory sourcekit-lsp opens (default: the project around the target).",
            valueName: "directory"))
    var workspace: String?

    @Option(name: .customLong("sourcekit-lsp"), help: ArgumentHelp("A sourcekit-lsp to run.", valueName: "path"))
    var sourceKitLSP: String?

    @OptionGroup(title: OptionGroupTitle.output) var output: FormatOptions
    @OptionGroup(title: OptionGroupTitle.cache) var cache: CacheOptions

    private struct Report: Encodable {
        let operation: String
        let target: String
        let locations: [String]?
        let calls: [Call]?
        let symbols: [Symbol]?
        let hover: String?
        var notes: [String]? = nil

        var isEmpty: Bool {
            (locations?.isEmpty ?? true) && (calls?.isEmpty ?? true) && (symbols?.isEmpty ?? true) && hover == nil
        }
    }

    private struct Call: Encodable {
        let symbol: String
        let kind: String
        let location: String
        let callSites: [String]
    }

    private struct Symbol: Encodable {
        let name: String
        let kind: String
        let container: String?
        let location: String
    }

    func run() async throws {
        try await runReportingErrors {
            let writer = Output(output)
            let format = { (position: SourcePosition) in
                "\(writer.path(position.file)):\(position.line):\(position.column)"
            }
            let position = operation == .symbols ? nil : try await resolveTarget()
            let root =
                workspace.map { SourcePath.absolute($0) }
                ?? ProjectLayout.discover(paths: [position?.file ?? SourcePath.absolute(".")])?.root
                ?? SourcePath.absolute(".")
            let report = try await SourceKitLSP.withSession(workspace: root, executable: sourceKitLSP) { session in
                let report = try await answer(session, at: position, format: format)
                guard report.isEmpty, let position, operation.readsIndex,
                    try await !session.indexHasRecord(at: position)
                else { return report }
                var noted = report
                noted.notes = [LanguageServerSession.unindexedNote(position)]
                return noted
            }
            if !output.quiet { for note in report.notes ?? [] { Diagnostics.note(note) } }
            try write(report, with: writer)
            return SearchOutcome.status(matchCount: report.isEmpty ? 0 : 1)
        }
    }

    private func answer(
        _ session: LanguageServerSession, at position: SourcePosition?, format: (SourcePosition) -> String
    ) async throws -> Report {
        func at() throws -> SourcePosition {
            guard let position else { throw ValidationError("\(operation.rawValue) needs a position") }
            return position
        }
        switch operation {
        case .symbols:
            let symbols = try await session.workspaceSymbols(target)
            return Report(
                operation: operation.rawValue, target: target, locations: nil, calls: nil,
                symbols: symbols.map {
                    Symbol(name: $0.name, kind: $0.kind, container: $0.container, location: format($0.position))
                }, hover: nil)
        case .hover:
            return Report(
                operation: operation.rawValue, target: target, locations: nil, calls: nil, symbols: nil,
                hover: try await session.hover(at: try at()))
        case .callers, .callees:
            let calls =
                operation == .callers
                ? try await session.callers(of: try at()) : try await session.callees(of: try at())
            return Report(
                operation: operation.rawValue, target: target, locations: nil,
                calls: calls.map {
                    Call(
                        symbol: $0.symbol.name, kind: $0.symbol.kind, location: format($0.symbol.position),
                        callSites: $0.callSites.map(format))
                }, symbols: nil, hover: nil)
        case .definition, .references, .implementations:
            let found =
                switch operation {
                case .definition: try await session.definition(at: try at())
                case .references: try await session.references(at: try at())
                default: try await session.implementations(at: try at())
                }
            return Report(
                operation: operation.rawValue, target: target, locations: found.map(format), calls: nil,
                symbols: nil, hover: nil)
        }
    }

    private func write(_ report: Report, with writer: Output) throws {
        switch output.format {
        case .json:
            try writer.json(report)
        case .text, .xcode:
            for location in report.locations ?? [] { try writer.write(location + "\n") }
            for call in report.calls ?? [] {
                try writer.write("\(call.location): \(call.kind) \(call.symbol)\n")
                for site in call.callSites { try writer.write("    \(site)\n") }
            }
            for symbol in report.symbols ?? [] {
                try writer.write(
                    "\(symbol.location): \(symbol.kind) " + (symbol.container.map { $0 + "." } ?? "") + symbol.name
                        + "\n")
            }
            if let hover = report.hover { try writer.write(hover + "\n") }
        }
    }

    /// `file:line:column`, or the one declaration a query names.
    private func resolveTarget() async throws -> SourcePosition {
        let parts = target.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 3, let line = Int(parts[parts.count - 2]), let column = Int(parts[parts.count - 1]),
            line >= 1, column >= 1
        {
            let file = SourcePath.absolute(parts.dropLast(2).joined(separator: ":"))
            return SourcePosition(file: file, line: line, column: column)
        }
        let paths = [workspace ?? "."]
        let search = try await SearchWorkspace.open(
            .init(paths: paths, cacheRoot: cache.noCache ? nil : (cache.cachePath ?? Corpus.defaultCacheRoot)))
        let matches = try search.find(SymbolQuery(pattern: try QueryParser.parse(target)))
        guard matches.count == 1, let match = matches.first else {
            if matches.isEmpty { throw ValidationError("no declaration matches '\(target)'") }
            let candidates = matches.prefix(20).map { "  \($0.qualifiedSelector) at \($0.location)" }
            throw ValidationError(
                "'\(target)' names \(matches.count) declarations; give a qualified name, a selector or "
                    + "file:line:column:\n" + candidates.joined(separator: "\n"))
        }
        return SourcePosition(file: match.file, line: match.line, column: match.column)
    }
}

extension LSP.Operation {
    /// Whether sourcekit-lsp answers the operation from its index.
    fileprivate var readsIndex: Bool {
        switch self {
        case .references, .implementations, .callers, .callees: true
        case .definition, .hover, .symbols: false
        }
    }
}
