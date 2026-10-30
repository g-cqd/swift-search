#if canImport(IndexStoreDB)
    internal import IndexStoreDB
    public import IndexStoreSupport
    internal import ProjectModel
    public import ReportSupport
    internal import SourceCorpus

    #if canImport(FoundationEssentials)
        internal import FoundationEssentials
    #else
        internal import Foundation
    #endif

    /// Answers queries from the compiler's index store: USRs, the module of a symbol, and the uses the compiler
    /// resolved to it.
    ///
    /// A fact is used only from a file whose unit is newer than the file (ADR-0005 of analyzerkit): a file changed
    /// since the build may have moved every line, so its index facts are not reported.
    public struct IndexStoreResolver: Sendable {
        public let session: IndexStoreSession

        public init(session: IndexStoreSession) {
            self.session = session
        }

        /// What opening a store for a corpus gave: a resolver, or the notes that say why there is none.
        public struct Opening: Sendable {
            public let resolver: IndexStoreResolver?
            public let notes: [RunNote]
            public let skippedFiles: [SkippedFile]
        }

        /// Opens the store at `path`, or the one discovered for `corpus` when `path` is nil (SwiftPM's under the
        /// project's `.build`, then the newest DerivedData store of its Xcode containers). The database is written
        /// under `cacheRoot`, never beside the store.
        public static func open(path: String?, corpus: Corpus, cacheRoot: String) async -> Opening {
            let store: String
            if let path {
                store = path
            } else {
                guard let layout = ProjectLayout.discover(paths: corpus.files),
                    let discovered = IndexStoreLocation.discover(
                        layout: layout, derivedDataRoots: [NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"])
                else {
                    return Opening(
                        resolver: nil,
                        notes: [
                            RunNote(
                                code: "index-not-found", severity: "warning",
                                message: "no index store was found for \(corpus.root); build the project, or pass "
                                    + "--index-store-path; the search ran on the syntax alone")
                        ], skippedFiles: [])
                }
                store = discovered
            }
            guard let library = await ToolchainResolution.resolve().libraryPath else {
                return Opening(
                    resolver: nil,
                    notes: [
                        RunNote(
                            code: "index-library-not-found", severity: "warning",
                            message: "no trusted libIndexStore.dylib was found; the search ran on the syntax alone")
                    ], skippedFiles: [])
            }
            switch IndexStoreSession.open(store, cacheRoot: cacheRoot, library: library, analyzedFiles: corpus.files) {
            case .usable(let session):
                return Opening(
                    resolver: IndexStoreResolver(session: session),
                    notes: session.coverage.runNotes(store: session.store, verbose: false),
                    skippedFiles: session.coverage.skippedFiles)
            case .notUsable(let store, let coverage):
                return Opening(
                    resolver: nil, notes: coverage.runNotes(store: store, verbose: false), skippedFiles: [])
            case .notAStore(let reason), .failed(let reason):
                return Opening(
                    resolver: nil, notes: [RunNote(code: "index-not-used", severity: "warning", message: reason)],
                    skippedFiles: [])
            }
        }

        // MARK: Definitions

        /// The definitions the store holds for `pattern`, in files whose unit is current.
        /// - Throws: ``QueryParseError/invalidRegex(_:reason:)`` for a regex that does not compile.
        /// - Complexity: O(*k*) in the canonical occurrences whose name starts with the pattern's name; every canonical
        ///   occurrence for a regex.
        public func definitions(_ pattern: SymbolQuery.Pattern) throws(QueryParseError) -> [SymbolMatch] {
            let database = session.database
            var found: [SymbolOccurrence] = []
            switch pattern {
            case .usr(let usr):
                found = database.occurrences(ofUSR: usr, roles: [.definition, .declaration])
            case .name(let name), .qualified(_, let name):
                database.forEachCanonicalSymbolOccurrence(
                    containing: name, anchorStart: true, anchorEnd: false, subsequence: false, ignoreCase: false
                ) { occurrence in
                    if Self.baseName(occurrence.symbol.name) == name { found.append(occurrence) }
                    return true
                }
            case .selector(_, let name, let labels):
                let spelled = name + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
                found = database.canonicalOccurrences(ofName: spelled)
            case .regex(let expression):
                let compiled = try NameExpression(expression)
                database.forEachCanonicalSymbolOccurrence(
                    containing: "", anchorStart: false, anchorEnd: false, subsequence: false, ignoreCase: false
                ) { occurrence in
                    if compiled.matches(Self.baseName(occurrence.symbol.name)) { found.append(occurrence) }
                    return true
                }
            }
            var seen: Set<String> = []
            var matches: [SymbolMatch] = []
            for occurrence in found
            where occurrence.roles.contains(.definition) || occurrence.roles.contains(.declaration) {
                let path = SourcePath.canonical(occurrence.location.path)
                guard !occurrence.location.isSystem, isCurrent(path) else { continue }
                let match = self.match(occurrence, path: path)
                guard seen.insert(match.location).inserted else { continue }
                switch pattern {
                case .qualified(let types, _), .selector(let types, _, _):
                    guard match.containers.count >= types.count, Array(match.containers.suffix(types.count)) == types
                    else { continue }
                default: break
                }
                matches.append(match)
            }
            return matches
        }

        /// `matches` with the USR and module the store records for each one's definition, when the file is current.
        /// - Complexity: O(*o*) in the occurrences of the files the matches are in, each file read once.
        public func enrich(_ matches: [SymbolMatch]) -> [SymbolMatch] {
            var byFile: [String: [SymbolOccurrence]] = [:]
            return matches.map { match in
                guard match.usr == nil, isCurrent(match.file) else { return match }
                let occurrences =
                    byFile[match.file]
                    ?? {
                        let read = session.database.symbolOccurrences(inFilePath: match.file).filter {
                            $0.roles.contains(.definition) || $0.roles.contains(.declaration)
                        }
                        byFile[match.file] = read
                        return read
                    }()
                let definition =
                    occurrences.first {
                        $0.location.line == match.line && $0.location.utf8Column == match.column
                            && Self.baseName($0.symbol.name) == match.name
                    }
                    ?? occurrences.first {
                        $0.location.line == match.line && Self.baseName($0.symbol.name) == match.name
                    }
                guard let definition else { return match }
                return match.with(usr: definition.symbol.usr, module: definition.location.moduleName)
            }
        }

        // MARK: Uses

        /// The uses the compiler resolved to `usr`, in files whose unit is current; and the files skipped because their
        /// unit is not.
        public func uses(ofUSR usr: String, symbol: String) -> (occurrences: [Usage], staleFiles: Set<String>) {
            var stale: Set<String> = []
            var uses: [Usage] = []
            let roles: SymbolRole = [.reference, .call, .read, .write]
            var spellings: [String: String] = [:]
            for occurrence in session.database.occurrences(ofUSR: usr, roles: roles)
            where !occurrence.roles.contains(.definition) && !occurrence.roles.contains(.declaration)
                && !occurrence.roles.contains(.implicit)
            {
                // The store records the paths the compiler was given; the corpus spells each file canonically.
                let recorded = occurrence.location.path
                let path = spellings[recorded] ?? SourcePath.canonical(recorded)
                spellings[recorded] = path
                guard isCurrent(path) else {
                    stale.insert(path)
                    continue
                }
                uses.append(
                    Usage(
                        file: path, line: occurrence.location.line, column: occurrence.location.utf8Column,
                        role: Self.role(occurrence.roles), symbol: symbol, isResolved: true))
            }
            return (Array(Set(uses)).sorted(), stale)
        }

        /// Whether `file`'s latest unit is at least as new as the file: answered from the coverage made when the store
        /// opened, or looked up once and remembered for the session (analyzerkit `IndexFreshness`).
        public func isCurrent(_ file: String) -> Bool {
            session.freshness.isCurrent(file)
        }

        // MARK: Conversion

        private func match(_ occurrence: SymbolOccurrence, path: String) -> SymbolMatch {
            let symbol = occurrence.symbol
            return SymbolMatch(
                name: Self.baseName(symbol.name), kind: Self.kind(symbol.kind),
                accessLevel: Self.access(symbol.properties),
                isStatic: [.staticMethod, .staticProperty, .classMethod, .classProperty].contains(symbol.kind),
                file: path, line: occurrence.location.line,
                column: occurrence.location.utf8Column, containers: containers(of: occurrence), usr: symbol.usr,
                module: occurrence.location.moduleName, source: .indexStore)
        }

        /// The enclosing types, outermost first, from `childOf` relations; at most 32 levels.
        private func containers(of occurrence: SymbolOccurrence) -> [String] {
            var names: [String] = []
            var current = occurrence
            for _ in 0..<32 {
                guard let parent = current.relations.first(where: { $0.roles.contains(.childOf) })?.symbol,
                    parent.kind != .module
                else { break }
                names.append(Self.baseName(parent.name))
                guard
                    let definition = session.database.occurrences(ofUSR: parent.usr, roles: [.definition]).first
                else { break }
                current = definition
            }
            return names.reversed()
        }

        /// `fetch` for `fetch(id:)`.
        static func baseName(_ name: String) -> String {
            guard let open = name.firstIndex(of: "("), open != name.startIndex else { return name }
            return String(name[..<open])
        }

        private static func kind(_ kind: IndexSymbolKind) -> DeclarationKind {
            switch kind {
            case .class: .class
            case .struct: .struct
            case .enum: .enum
            case .protocol: .protocol
            case .extension: .extension
            case .typealias: .typealias
            case .function, .conversionFunction: .function
            case .instanceMethod, .classMethod, .staticMethod: .method
            case .constructor: .initializer
            case .destructor: .deinitializer
            case .enumConstant: .enumCase
            case .macro: .macro
            case .variable, .field, .instanceProperty, .classProperty, .staticProperty, .parameter: .variable
            default: .variable
            }
        }

        private static func access(_ properties: SymbolProperty) -> AccessLevel {
            if properties.contains(.swiftAccessControlPublic) { return .public }
            if properties.contains(.swiftAccessControlPackage) { return .package }
            if properties.contains(.swiftAccessControlFileprivate) { return .fileprivate }
            if properties.contains(.swiftAccessControlLessThanFilePrivate) { return .private }
            return .internal
        }

        private static func role(_ roles: SymbolRole) -> Usage.Role {
            if roles.contains(.call) { return .call }
            if roles.contains(.write) { return .write }
            if roles.contains(.read) { return .read }
            return .reference
        }
    }
#endif
