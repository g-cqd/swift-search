/// Reads the query language of the command line and of the MCP tools.
///
/// | Input | Pattern |
/// | --- | --- |
/// | `shared` | ``SymbolQuery/Pattern/name(_:)`` |
/// | `Outer.Inner.member` | ``SymbolQuery/Pattern/qualified(types:name:)`` |
/// | `fetch(id:_:)`, `Type.fetch()` | ``SymbolQuery/Pattern/selector(types:name:labels:)`` |
/// | `s:4main3FooV`, `c:objc(cs)NSObject` | ``SymbolQuery/Pattern/usr(_:)`` |
/// | `/Network.*/` | ``SymbolQuery/Pattern/regex(_:)``, RE2 syntax, matched against the whole name |
public enum QueryParser {
    /// The longest query accepted, in UTF-8 bytes; a query is attacker input over MCP.
    public static let maximumLength = 4096

    /// The pattern `input` spells.
    /// - Throws: ``QueryParseError`` for an empty, overlong or malformed query.
    /// - Complexity: O(*n*) in the length of `input`, plus compiling a regex.
    public static func parse(_ input: String) throws(QueryParseError) -> SymbolQuery.Pattern {
        let text = input.trimmingWhitespace()
        guard !text.isEmpty else { throw .empty }
        guard text.utf8.count <= maximumLength else { throw .tooLong(maximumLength) }
        if isUSR(text) { return .usr(text) }
        if text.count > 2, text.hasPrefix("/"), text.hasSuffix("/") {
            let expression = String(text.dropFirst().dropLast())
            _ = try NameExpression(expression)
            return .regex(expression)
        }
        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let labels = try selectorLabels(String(text[text.index(after: open)..<text.index(before: text.endIndex)]))
            let path = try components(String(text[..<open]), whole: text)
            return .selector(types: Array(path.dropLast()), name: path[path.count - 1], labels: labels)
        }
        let path = try components(text, whole: text)
        if path.count == 1 { return .name(path[0]) }
        return .qualified(types: Array(path.dropLast()), name: path[path.count - 1])
    }

    /// Whether `text` is a Swift (`s:`) or Clang (`c:`) USR.
    public static func isUSR(_ text: String) -> Bool {
        text.count > 2 && (text.hasPrefix("s:") || text.hasPrefix("c:"))
    }

    /// `Outer.Inner<T>.member` split on the dots outside generic brackets; every component non-empty and free of
    /// spaces.
    private static func components(_ text: String, whole: String) throws(QueryParseError) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "<":
                depth += 1
                current.append(character)
            case ">":
                depth -= 1
                guard depth >= 0 else { throw .invalidName(whole) }
                current.append(character)
            case "." where depth == 0:
                guard !current.isEmpty else { throw .invalidName(whole) }
                parts.append(current)
                current = ""
            case " ", "\t", "\n", "\r":
                throw .invalidName(whole)
            default:
                current.append(character)
            }
        }
        guard depth == 0, !current.isEmpty else { throw .invalidName(whole) }
        parts.append(current)
        return parts
    }

    /// `id:_:name:` as `["id", nil, "name"]`; empty for `()`.
    private static func selectorLabels(_ text: String) throws(QueryParseError) -> [String?] {
        let content = text.trimmingWhitespace()
        guard !content.isEmpty else { return [] }
        guard content.hasSuffix(":") else { throw .invalidSelector(text) }
        var labels: [String?] = []
        for part in content.dropLast().split(separator: ":", omittingEmptySubsequences: false) {
            let label = String(part).trimmingWhitespace()
            guard !label.isEmpty, !label.contains(" ") else { throw .invalidSelector(text) }
            labels.append(label == "_" ? nil : label)
        }
        return labels
    }
}

/// Why a query was refused.
public enum QueryParseError: Error, Sendable, Equatable, CustomStringConvertible {
    case empty
    case tooLong(Int)
    case invalidName(String)
    case invalidSelector(String)
    case invalidRegex(String, reason: String)

    public var description: String {
        switch self {
        case .empty: "the query is empty"
        case .tooLong(let limit): "the query is longer than \(limit) bytes"
        case .invalidName(let name): "'\(name)' is not a name, a qualified name (Type.member) or a selector (f(x:))"
        case .invalidSelector(let text): "'(\(text))' is not a selector's labels: write (label:_:) or ()"
        case .invalidRegex(let expression, let reason): "/\(expression)/ is not a regular expression: \(reason)"
        }
    }
}

extension String {
    /// The string without leading and trailing spaces, tabs and line breaks.
    func trimmingWhitespace() -> String {
        let blank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        return String(drop(while: blank).reversed().drop(while: blank).reversed())
    }
}
