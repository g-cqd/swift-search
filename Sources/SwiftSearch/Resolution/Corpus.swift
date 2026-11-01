internal import CorpusScan
// ObjCBool, which `fileExists(atPath:isDirectory:)` takes, is not in FoundationEssentials on Linux.
internal import Foundation
internal import ProjectModel
public import ReportSupport
internal import SourceCorpus

/// The Swift files under a set of paths, with their symbols.
public struct Corpus: Sendable {
    /// The canonical paths of the Swift files found.
    public let files: [String]
    /// The project the paths belong to: a package or Xcode project root, else the repository, else their common
    /// directory.
    public let root: String
    public let table: SymbolTable
    /// What the load could not do: files skipped, directories not read, a cache not used.
    public let notes: [RunNote]
    public let skippedFiles: [SkippedFile]
    public let cacheHits: Int

    /// The Swift files under `paths`, less those `exclude` matches.
    ///
    /// A directory is walked without following links out of it, and build products, VCS internals and dependency
    /// checkouts are not entered (analyzerkit `SourceDiscovery`); a file given by name is kept whatever its extension.
    /// - Throws: ``SearchError/pathNotFound(_:)``, ``SearchError/noSwiftFiles(_:)``.
    public static func discover(paths: [String], exclude: [String] = []) throws(SearchError)
        -> (files: [String], root: String, unreadableDirectories: [String])
    {
        let given = paths.isEmpty ? ["."] : paths
        let absolute = given.map { $0.hasPrefix("/") ? $0 : FileManager.default.currentDirectoryPath + "/" + $0 }
        let root = ProjectLayout.discover(paths: absolute)?.root ?? SourcePath.canonical(absolute[0])
        let filter = PathFilter(exclude, root: root)
        var files: [String] = []
        var unreadable: [String] = []
        for (path, spelled) in zip(absolute, given) {
            var isDirectory: ObjCBool = false
            guard unsafe FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw .pathNotFound(spelled)
            }
            if isDirectory.boolValue {
                let found = SourceDiscovery.discover(under: path) { filter.excludes($0) }
                files += found.files
                unreadable += found.unreadableDirectories
            } else if !filter.excludes(path) {
                files.append(path)
            }
        }
        let canonical = SourcePath.canonicalized(files)
        guard !canonical.isEmpty else { throw .noSwiftFiles(given) }
        return (canonical, root, unreadable)
    }

    /// Reads the symbols of the Swift files under `paths`, reusing the facts cache for files whose bytes did not change.
    ///
    /// Files are read and parsed in parallel, at most one per core in flight (analyzerkit `CorpusScanner`).
    /// - Parameters:
    ///   - cacheRoot: the cache directory, or nil for no cache.
    /// - Throws: ``SearchError``; `CancellationError` when the caller is cancelled.
    /// - Complexity: O(*n*) in the corpus size over the available cores; O(*c*) for a warm cache of *c* files.
    public static func load(paths: [String], exclude: [String] = [], cacheRoot: String?) async throws -> Corpus {
        let found = try discover(paths: paths, exclude: exclude)
        let cache = cacheRoot.map { CacheLocation(root: $0, workspace: found.root) }
        let scan = try await CorpusScanner.scan(
            paths: found.files, cache: cache,
            identity: CacheIdentity.current(tool: ToolInfo.name, version: ToolInfo.version)
        ) { path, bytes in SymbolExtractor.extract(bytes: bytes, path: path) }
        var symbols: [FileSymbols] = []
        var unreadable: [String] = []
        var degraded: [String] = []
        for file in scan.files {
            if file.failure != nil {
                unreadable.append(file.path)
            } else if let facts = file.facts {
                if facts.degraded != nil { degraded.append(file.path) }
                symbols.append(facts)
            }
        }
        var notes: [RunNote] = []
        if !unreadable.isEmpty {
            notes.append(
                RunNote(
                    code: "unreadable-files", severity: "warning",
                    message: "\(unreadable.count) file(s) could not be read; their symbols are not searched",
                    paths: unreadable))
        }
        if !degraded.isEmpty {
            notes.append(
                RunNote(
                    code: "degraded-files", severity: "warning",
                    message: "\(degraded.count) file(s) nest too deeply to walk; their symbols are not searched",
                    paths: degraded))
        }
        if !found.unreadableDirectories.isEmpty {
            notes.append(
                RunNote(
                    code: "unreadable-directories", severity: "warning",
                    message: "\(found.unreadableDirectories.count) directory(ies) could not be listed",
                    paths: found.unreadableDirectories))
        }
        if let failure = scan.cacheLoadFailure {
            notes.append(RunNote(code: "cache-not-used", severity: "note", message: failure))
        }
        return Corpus(
            files: found.files, root: found.root, table: SymbolTable(symbols), notes: notes,
            skippedFiles: unreadable.map { SkippedFile(path: $0, reason: .unreadable) }
                + degraded.map { SkippedFile(path: $0, reason: .degraded) },
            cacheHits: scan.cacheHits)
    }

    /// The facts cache's default directory: `~/Library/Caches/swift-search` on macOS.
    public static var defaultCacheRoot: String {
        let environment = ProcessInfo.processInfo.environment
        return CacheLocation.defaultRoot(
            tool: ToolInfo.name, environment: environment, home: environment["HOME"] ?? "/tmp")
    }
}
