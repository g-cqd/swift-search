public import ReportSupport

/// A corpus ready to answer queries: its symbols from the syntax, and the compiler's index store when one was asked for
/// and covers it.
public struct SearchWorkspace: Sendable {
    /// Whether and where to read the compiler's index store.
    public enum IndexStoreRequest: Sendable, Equatable {
        /// The syntax alone.
        case none
        /// The store discovered for the project.
        case discover
        /// The store at this path.
        case path(String)
    }

    /// What a workspace is opened over.
    public struct Options: Sendable {
        public var paths: [String]
        public var exclude: [String]
        /// The facts cache and index database directory; nil for no facts cache (the index database then goes to the
        /// default cache directory, never beside the store).
        public var cacheRoot: String?
        public var indexStore: IndexStoreRequest

        public init(
            paths: [String] = ["."], exclude: [String] = [], cacheRoot: String? = Corpus.defaultCacheRoot,
            indexStore: IndexStoreRequest = .none
        ) {
            self.paths = paths
            self.exclude = exclude
            self.cacheRoot = cacheRoot
            self.indexStore = indexStore
        }
    }

    /// The usages of the declarations a query matched.
    public struct UsageReport: Sendable, Codable {
        public let matches: [SymbolMatch]
        public let usages: [Usage]
    }

    public let corpus: Corpus
    /// What opening the workspace could not do; the search still ran on what it could.
    public let notes: [RunNote]
    public let skippedFiles: [SkippedFile]
    #if canImport(IndexStoreDB)
        public let index: IndexStoreResolver?
    #endif
    private let corpusFiles: Set<String>

    /// Reads the corpus, then opens the index store when `options` asks for one.
    /// - Throws: ``SearchError`` for a missing path or no Swift file; `CancellationError`.
    public static func open(_ options: Options) async throws -> SearchWorkspace {
        let corpus = try await Corpus.load(paths: options.paths, exclude: options.exclude, cacheRoot: options.cacheRoot)
        var notes = corpus.notes
        var skipped = corpus.skippedFiles
        #if canImport(IndexStoreDB)
            var index: IndexStoreResolver?
            let path: String?
            switch options.indexStore {
            case .none: path = nil
            case .discover: path = nil
            case .path(let given): path = given
            }
            if options.indexStore != .none {
                let opening = await IndexStoreResolver.open(
                    path: path, corpus: corpus, cacheRoot: options.cacheRoot ?? Corpus.defaultCacheRoot)
                index = opening.resolver
                notes += opening.notes
                skipped += opening.skippedFiles
            }
            return SearchWorkspace(corpus: corpus, notes: notes, skippedFiles: skipped, index: index)
        #else
            if options.indexStore != .none {
                notes.append(
                    RunNote(
                        code: "index-unsupported", severity: "warning",
                        message: "the index store is read on macOS only; the search ran on the syntax alone"))
            }
            return SearchWorkspace(corpus: corpus, notes: notes, skippedFiles: skipped)
        #endif
    }

    #if canImport(IndexStoreDB)
        init(corpus: Corpus, notes: [RunNote], skippedFiles: [SkippedFile], index: IndexStoreResolver?) {
            self.corpus = corpus
            self.notes = notes
            self.skippedFiles = skippedFiles
            self.index = index
            self.corpusFiles = Set(corpus.files)
        }
    #else
        init(corpus: Corpus, notes: [RunNote], skippedFiles: [SkippedFile]) {
            self.corpus = corpus
            self.notes = notes
            self.skippedFiles = skippedFiles
            self.corpusFiles = Set(corpus.files)
        }
    #endif

    /// Whether the index store is open.
    public var hasIndexStore: Bool {
        #if canImport(IndexStoreDB)
            index != nil
        #else
            false
        #endif
    }

    /// The declarations `query` names, filtered, sorted by location, then cut at its limit.
    ///
    /// The syntax answers for the corpus. With an index store, its matches gain their USR and module, and definitions
    /// in current files outside the corpus (other packages of the build) are added; a USR is answered by the store
    /// alone, described by the syntax when its definition is in the corpus.
    /// - Throws: ``SearchError/usrNeedsIndexStore(_:)`` for a USR without a store; ``SearchError/query(_:)`` for a
    ///   regex that does not compile.
    public func find(_ query: SymbolQuery) throws(SearchError) -> [SymbolMatch] {
        if case .usr(let usr) = query.pattern, !hasIndexStore { throw .usrNeedsIndexStore(usr) }
        var matches: [SymbolMatch]
        do throws(QueryParseError) {
            matches = try SyntaxResolver.resolve(query.pattern, in: corpus.table)
            #if canImport(IndexStoreDB)
                if let index {
                    let indexed = try index.definitions(query.pattern)
                    if case .usr = query.pattern {
                        // The syntax knows no USR; it still describes a corpus declaration best (signature, generics).
                        matches = indexed.map { match in
                            corpus.table.declarations(named: match.name).first {
                                $0.file == match.file && $0.declaration.line == match.line
                            }.map {
                                SymbolMatch($0.declaration, file: $0.file).with(usr: match.usr, module: match.module)
                            }
                                ?? match
                        }
                    } else {
                        matches = index.enrich(matches) + indexed.filter { !corpusFiles.contains($0.file) }
                    }
                }
            #endif
        } catch {
            throw .query(error)
        }
        var seen: Set<String> = []
        let kept = matches.filter { query.admits($0) && seen.insert($0.location).inserted }.sorted()
        return query.limit.map { Array(kept.prefix(max($0, 0))) } ?? kept
    }

    /// The declarations `query` names and their usages, sorted by location.
    ///
    /// With an index store, a declaration that has a USR gets the uses the compiler resolved to it; files whose unit is
    /// older than the file fall back to the syntax. Without one, every reference to the name is reported, marked
    /// unresolved, except one through a base that names another type of the corpus.
    public func usages(of query: SymbolQuery) throws(SearchError) -> UsageReport {
        let matches = try find(query)
        var usages: Set<Usage> = []
        for match in matches {
            #if canImport(IndexStoreDB)
                if let index, let usr = match.usr {
                    let resolved: [Usage] = index.uses(ofUSR: usr, symbol: match.qualifiedSelector).occurrences
                    let unindexed: [Usage] = SyntaxResolver.uses(of: match, in: corpus.table).filter { usage in
                        !index.isCurrent(usage.file)
                    }
                    usages.formUnion(resolved)
                    usages.formUnion(unindexed)
                    continue
                }
            #endif
            usages.formUnion(SyntaxResolver.uses(of: match, in: corpus.table))
        }
        return UsageReport(matches: matches, usages: usages.sorted())
    }
}
