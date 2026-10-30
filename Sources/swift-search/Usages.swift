internal import AnalyzerCLI
internal import ArgumentParser
internal import ReportSupport
internal import SwiftSearch

/// `swift-search usages`: where the declarations a query names are used.
struct Usages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find where the declarations a query names are used.",
        discussion: """
            With --index-store, only the uses the compiler resolved to them are reported; files changed since the \
            build fall back to the syntax. Without it, every use of the name is reported, except through a base \
            that names another type, and marked unresolved.
            """)

    @Argument(help: "Name, Type.member, selector f(x:), /regex/ or USR.")
    var query: String

    @OptionGroup(title: "Input") var input: SearchInputOptions
    @OptionGroup(title: "Filters") var filters: FilterOptions
    @OptionGroup(title: OptionGroupTitle.output) var output: FormatOptions
    @OptionGroup(title: OptionGroupTitle.cache) var cache: CacheOptions
    @OptionGroup(title: OptionGroupTitle.index) var index: IndexOptions

    private struct Report: Encodable {
        let query: String
        let matches: [MatchRecord]
        let usages: [UsageRecord]
    }

    func run() async throws {
        try await runReportingErrors {
            // The limit counts usages here, not declarations.
            let unlimited = try filters.query(self.query)
            let query = SymbolQuery(
                pattern: unlimited.pattern, kinds: unlimited.kinds, accessLevels: unlimited.accessLevels,
                containingType: unlimited.containingType)
            let workspace = try await SearchWorkspace.open(.init(input: input, cache: cache, index: index))
            Output.notes(workspace.notes, quiet: output.quiet)
            let report = try workspace.usages(of: query)
            let usages = filters.limit.map { Array(report.usages.prefix($0)) } ?? report.usages
            let writer = Output(output)
            let records = usages.map { UsageRecord($0, path: writer.path) }
            switch output.format {
            case .json:
                try writer.json(
                    ReportEnvelope(
                        Report(
                            query: self.query, matches: report.matches.map { MatchRecord($0, path: writer.path) },
                            usages: records), tool: ToolInfo.name, version: ToolInfo.version,
                        runNotes: workspace.notes, skippedFiles: workspace.skippedFiles))
            case .xcode:
                for usage in usages {
                    try writer.write(
                        XcodeDiagnostic.line(
                            path: writer.path(usage.file), line: usage.line, column: usage.column, severity: "note",
                            rule: nil, message: "\(usage.role.rawValue) of '\(usage.symbol)'") + "\n")
                }
            case .text:
                for record in records {
                    try writer.write(
                        "\(record.location): \(record.role.rawValue) \(record.symbol)"
                            + (record.resolved ? "" : " (by name)") + "\n")
                }
            }
            if report.matches.isEmpty, !output.quiet { Diagnostics.note("no declaration matches '\(self.query)'") }
            return workspace.status(matchCount: usages.count)
        }
    }
}
