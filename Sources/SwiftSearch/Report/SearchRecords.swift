/// A match as the JSON reports and the MCP tools write it: compact, with its path as presented.
public struct MatchRecord: Sendable, Codable, Equatable {
    /// `Outer.Inner.fetch(id:)`.
    public let symbol: String
    public let kind: DeclarationKind
    public let access: AccessLevel
    /// Present and true for a static or class member only.
    public let isStatic: Bool?
    /// `path:line:column`, the column in UTF-8 bytes.
    public let location: String
    /// `(id: Int) -> Data` for a callable, the declared type for a variable.
    public let signature: String?
    public let genericParameters: [String]?
    public let usr: String?
    public let module: String?
    public let source: SymbolMatch.Source
    public let context: SymbolContext?

    /// - Parameter path: how the record spells a file, e.g. relative to the project root.
    public init(_ match: SymbolMatch, path: (String) -> String, context: SymbolContext? = nil) {
        symbol = match.qualifiedSelector
        kind = match.kind
        access = match.accessLevel
        isStatic = match.isStatic ? true : nil
        location = "\(path(match.file)):\(match.line):\(match.column)"
        signature = match.signature?.display ?? match.typeAnnotation
        genericParameters = match.genericParameters.isEmpty ? nil : match.genericParameters
        usr = match.usr
        module = match.module
        source = match.source
        self.context = context
    }
}

/// A usage as the JSON reports and the MCP tools write it.
public struct UsageRecord: Sendable, Codable, Equatable {
    /// `path:line:column`, the column in UTF-8 bytes.
    public let location: String
    public let role: Usage.Role
    public let symbol: String
    /// Whether the compiler resolved the use to the symbol (index store); false when only its name matched.
    public let resolved: Bool

    public init(_ usage: Usage, path: (String) -> String) {
        location = "\(path(usage.file)):\(usage.line):\(usage.column)"
        role = usage.role
        symbol = usage.symbol
        resolved = usage.isResolved
    }
}
