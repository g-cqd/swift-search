/// One place a symbol is used.
public struct Usage: Sendable, Hashable, Codable {
    /// How the symbol is used there.
    public enum Role: String, Sendable, Hashable, Codable {
        case reference
        case call
        case read
        case write
        case type
    }

    public let file: String
    public let line: Int
    /// The 1-based UTF-8 column.
    public let column: Int
    public let role: Role
    /// The symbol used, `qualifiedSelector` of its match.
    public let symbol: String
    /// Whether the compiler resolved the use to the symbol (index store), or only its name matched (syntax).
    public let isResolved: Bool

    public init(file: String, line: Int, column: Int, role: Role, symbol: String, isResolved: Bool) {
        self.file = file
        self.line = line
        self.column = column
        self.role = role
        self.symbol = symbol
        self.isResolved = isResolved
    }

    /// `file:line:column`.
    public var location: String { "\(file):\(line):\(column)" }
}

extension Usage: Comparable {
    /// By file, line, then column.
    public static func < (lhs: Usage, rhs: Usage) -> Bool {
        (lhs.file, lhs.line, lhs.column) < (rhs.file, rhs.line, rhs.column)
    }
}
