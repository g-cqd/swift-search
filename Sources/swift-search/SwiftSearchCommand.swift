internal import AnalyzerCLI
public import ArgumentParser
public import SwiftSearch

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

@main
struct SwiftSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-search",
        abstract: "Find Swift declarations and their uses, from the sources, the index store or sourcekit-lsp.",
        discussion: """
            Queries: a name (shared), a qualified name (Client.shared), a selector (fetch(id:_:)), a regex over whole \
            names (/load.*/, RE2 syntax), or a USR (s:...; needs --index-store).

            Exit status: 0 when something was found, 1 when nothing was, 64 for a usage error (a path that does not \
            exist, no Swift file, a malformed query), 70 for an internal failure, 74 when the output could not be \
            written.
            """,
        version: ToolInfo.version,
        subcommands: [Find.self, Usages.self, LSP.self, MCP.self],
        defaultSubcommand: Find.self)
}

/// What to search: the paths and what to leave out of them.
struct SearchInputOptions: ParsableArguments {
    @Argument(help: "Swift files or directories to search.")
    var paths: [String] = ["."]

    @Option(
        name: .customLong("exclude-path"),
        help: ArgumentHelp(
            "Leave out the paths matching this pattern (repeatable): a substring, or a glob with *, ? or [.",
            valueName: "pattern"))
    var excludePaths: [String] = []
}

/// The filters every query takes.
struct FilterOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Only this declaration kind (repeatable).", valueName: "kind"))
    var kind: [DeclarationKind] = []

    @Option(help: ArgumentHelp("Only this access level (repeatable).", valueName: "level"))
    var access: [AccessLevel] = []

    @Option(
        name: .customLong("in-type"), help: ArgumentHelp("Only members of this type or extension.", valueName: "type"))
    var inType: String?

    @Option(help: "At most this many results.")
    var limit: Int?

    func validate() throws {
        if let limit, limit < 1 { throw ValidationError("--limit must be at least 1") }
    }

    func query(_ text: String) throws -> SymbolQuery {
        SymbolQuery(
            pattern: try QueryParser.parse(text), kinds: Set(kind), accessLevels: Set(access), containingType: inType,
            limit: limit)
    }
}

/// How results are written.
struct FormatOptions: ParsableArguments {
    enum Format: String, CaseIterable, ExpressibleByArgument { case text, xcode, json }

    @Option(help: "Output format: text, xcode (build-log notes) or json.")
    var format: Format = .text

    @Option(
        name: .customLong("relative-to"),
        help: ArgumentHelp("Report paths relative to this directory.", valueName: "directory"))
    var relativeTo: String?

    @Flag(help: "Print nothing on stderr but errors.")
    var quiet = false
}

extension DeclarationKind: ExpressibleByArgument {}
extension AccessLevel: ExpressibleByArgument {}

extension SearchWorkspace.Options {
    /// The options the command line gives.
    init(input: SearchInputOptions, cache: CacheOptions, index: IndexOptions) throws {
        guard !index.indexStoreBuild else {
            throw ValidationError("--index-store-build is not supported: build the project, then pass --index-store")
        }
        let request: SearchWorkspace.IndexStoreRequest =
            index.indexStorePath.map { .path($0) } ?? (index.requested ? .discover : .none)
        self.init(
            paths: input.paths, exclude: input.excludePaths,
            cacheRoot: cache.noCache ? nil : (cache.cachePath ?? Corpus.defaultCacheRoot), indexStore: request)
    }
}

/// Runs `body`, mapping the status it returns and the search's errors to exit statuses: 0 found, 1 nothing found, 70
/// nothing readable (analyzerkit `SearchOutcome`, ADR-0026), and the family's 64, 70 and 74 (ADR-0018).
func runReportingErrors(_ body: () async throws -> ExitStatus) async throws {
    let status: Int32
    do {
        status = try await body().rawValue
    } catch let error as SearchError {
        Diagnostics.error(error.description)
        status = ExitStatus.usage.rawValue
    } catch let error as QueryParseError {
        Diagnostics.error(error.description)
        status = ExitStatus.usage.rawValue
    } catch let error as OutputError {
        Diagnostics.error(error.description)
        status = ExitStatus.outputFailure.rawValue
    } catch is CancellationError {
        status = ExitStatus.internalFailure.rawValue
    }
    if status != 0 { throw ExitCode(status) }
}

/// Lines on standard error.
enum Diagnostics {
    static func error(_ message: String) {
        FileHandle.standardError.write(Data("swift-search: error: \(message)\n".utf8))
    }

    static func note(_ message: String) {
        FileHandle.standardError.write(Data("swift-search: note: \(message)\n".utf8))
    }
}

extension SearchWorkspace {
    /// The status of a search over this workspace that printed `matchCount` matches.
    func status(matchCount: Int) -> ExitStatus {
        let skipped = corpus.skippedFiles.count
        return SearchOutcome.status(
            matchCount: matchCount, analyzedFileCount: corpus.files.count - skipped, skippedFileCount: skipped)
    }
}
