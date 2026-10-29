internal import SourceCorpus

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

extension SourcePath {
    /// `path` made absolute against the current directory, then canonical.
    static func absolute(_ path: String) -> String {
        canonical(path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path)
    }
}
