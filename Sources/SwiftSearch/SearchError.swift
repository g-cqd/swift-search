/// Why a search could not run.
public enum SearchError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A path given does not exist.
    case pathNotFound(String)
    /// No Swift file under the paths given.
    case noSwiftFiles([String])
    /// The query does not parse.
    case query(QueryParseError)
    /// A USR was asked for without an index store: only the compiler's index knows USRs.
    case usrNeedsIndexStore(String)

    public var description: String {
        switch self {
        case .pathNotFound(let path): "\(path): no such file or directory"
        case .noSwiftFiles(let paths): "no Swift file under \(paths.joined(separator: ", "))"
        case .query(let error): error.description
        case .usrNeedsIndexStore(let usr):
            "\(usr) is a USR, which only the compiler's index store resolves; pass --index-store or --index-store-path"
        }
    }
}
