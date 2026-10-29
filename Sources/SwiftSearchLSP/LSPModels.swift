/// A place in a file: 1-based line, 1-based UTF-8 column, as every match and usage of swift-search reports it.
public struct SourcePosition: Sendable, Hashable, Codable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// A symbol sourcekit-lsp reports: from `workspace/symbol` or a call hierarchy.
public struct LanguageServerSymbol: Sendable, Hashable, Codable {
    public let name: String
    /// The LSP `SymbolKind` name: `class`, `method`, `property`.
    public let kind: String
    public let container: String?
    public let position: SourcePosition
    /// The signature or type sourcekit-lsp gives as a detail, when it gives one.
    public let detail: String?

    public init(name: String, kind: String, container: String?, position: SourcePosition, detail: String?) {
        self.name = name
        self.kind = kind
        self.container = container
        self.position = position
        self.detail = detail
    }
}

/// A call between two symbols: the other end, and where in the caller the calls are.
public struct LanguageServerCall: Sendable, Hashable, Codable {
    public let symbol: LanguageServerSymbol
    public let callSites: [SourcePosition]
}

/// The LSP `SymbolKind` names, by number (LSP 3.17).
enum SymbolKindName {
    private static let names = [
        "file", "module", "namespace", "package", "class", "method", "property", "field", "constructor", "enum",
        "interface", "function", "variable", "constant", "string", "number", "boolean", "array", "object", "key",
        "null", "enumMember", "struct", "event", "operator", "typeParameter",
    ]

    static func name(_ number: Int) -> String {
        (1...names.count).contains(number) ? names[number - 1] : "unknown"
    }
}
