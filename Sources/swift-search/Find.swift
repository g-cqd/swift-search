internal import AnalyzerCLI
internal import ArgumentParser
internal import ReportSupport
internal import SwiftSearch

/// `swift-search find`: the declarations a query names.
struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Find the declarations a query names.")

    @Argument(help: "Name, Type.member, selector f(x:), /regex/ or USR.")
    var query: String

    @OptionGroup(title: "Input") var input: SearchInputOptions
    @OptionGroup(title: "Filters") var filters: FilterOptions
    @OptionGroup(title: "Context") var context: ContextOptions
    @OptionGroup(title: OptionGroupTitle.output) var output: FormatOptions
    @OptionGroup(title: OptionGroupTitle.cache) var cache: CacheOptions
    @OptionGroup(title: OptionGroupTitle.index) var index: IndexOptions

    private struct Report: Encodable {
        let query: String
        let matches: [MatchRecord]
    }

    func run() async throws {
        try await runReportingErrors {
            let query = try filters.query(self.query)
            let workspace = try await SearchWorkspace.open(.init(input: input, cache: cache, index: index))
            Output.notes(workspace.notes, quiet: output.quiet)
            let matches = try workspace.find(query)
            let writer = Output(output)
            let options = context.options
            var records: [MatchRecord] = []
            for match in matches {
                let found =
                    options.isEmpty
                    ? nil
                    : await SymbolContextExtractor.context(
                        file: match.file, line: match.line, column: match.column, options: options)
                records.append(MatchRecord(match, path: writer.path, context: found))
            }
            switch output.format {
            case .json:
                try writer.json(
                    ReportEnvelope(
                        Report(query: self.query, matches: records), tool: ToolInfo.name, version: ToolInfo.version,
                        runNotes: workspace.notes, skippedFiles: workspace.skippedFiles))
            case .xcode:
                for (record, match) in zip(records, matches) {
                    try writer.write(
                        XcodeDiagnostic.line(
                            path: writer.path(match.file), line: match.line, column: match.column, severity: "note",
                            rule: nil, message: "\(record.kind.rawValue) '\(record.symbol)'") + "\n")
                }
            case .text:
                for record in records { try writer.write(writer.text(record) + "\n") }
            }
            return workspace.status(matchCount: matches.count)
        }
    }
}

/// What to show around each declaration.
struct ContextOptions: ParsableArguments {
    @Option(name: .customLong("context-lines"), help: "Lines of source before and after each declaration.")
    var lines: Int = 0

    @Flag(help: "Show each declaration up to its body.")
    var signature = false

    @Flag(help: "Show each body (at most 400 lines).")
    var body = false

    @Flag(help: "Show each documentation comment.")
    var documentation = false

    @Flag(help: "Show the enclosing type or function.")
    var scope = false

    @Flag(name: .customLong("context-all"), help: "Five lines either side, signature, body, documentation and scope.")
    var all = false

    func validate() throws {
        guard (0...SymbolContextOptions.maximumContextLines).contains(lines) else {
            throw ValidationError("--context-lines must be in 0...\(SymbolContextOptions.maximumContextLines)")
        }
    }

    var options: SymbolContextOptions {
        all
            ? .all
            : SymbolContextOptions(
                linesBefore: lines, linesAfter: lines, signature: signature, body: body, documentation: documentation,
                scope: scope)
    }
}
