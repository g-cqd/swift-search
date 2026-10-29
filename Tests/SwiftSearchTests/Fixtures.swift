import Foundation

@testable import SwiftSearch

/// A directory of Swift files under the temporary directory, removed by ``remove()``.
struct TemporaryCorpus {
    let root: String

    init(_ files: [String: String]) throws {
        // The spelling the corpus uses for every file (analyzerkit `SourcePath.canonical`).
        root =
            FileManager.default.temporaryDirectory.appendingPathComponent("swift-search-\(UUID().uuidString)")
            .standardized.resolvingSymlinksInPath().path
        for (name, text) in files {
            let path = root + "/" + name
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func path(_ name: String) -> String { root + "/" + name }

    func remove() { try? FileManager.default.removeItem(atPath: root) }
}

/// The symbols of `source`, extracted as the scan does.
func symbols(_ source: String, path: String = "/fixture/File.swift") -> FileSymbols {
    SymbolExtractor.extract(source: source, path: path)
}

/// A table over one file of `source`.
func table(_ source: String, path: String = "/fixture/File.swift") -> SymbolTable {
    SymbolTable([symbols(source, path: path)])
}
