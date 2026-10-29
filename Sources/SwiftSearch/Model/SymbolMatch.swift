/// A declaration that answers a query.
public struct SymbolMatch: Sendable, Hashable, Codable {
    /// Where the match came from.
    public enum Source: String, Sendable, Hashable, Codable {
        /// The syntax of a source file in the corpus.
        case syntax
        /// The compiler's index store.
        case indexStore
        /// sourcekit-lsp.
        case languageServer
    }

    public let name: String
    public let kind: DeclarationKind
    public let accessLevel: AccessLevel
    public let isStatic: Bool
    public let file: String
    public let line: Int
    /// The 1-based UTF-8 column.
    public let column: Int
    /// The enclosing types and extensions, outermost first.
    public let containers: [String]
    /// The Unified Symbol Resolution, when the index store gave one.
    public let usr: String?
    /// The module, when the index store gave one.
    public let module: String?
    public let typeAnnotation: String?
    public let genericParameters: [String]
    public let signature: FunctionSignature?
    public let source: Source

    public init(
        name: String, kind: DeclarationKind, accessLevel: AccessLevel, isStatic: Bool = false, file: String, line: Int,
        column: Int, containers: [String] = [], usr: String? = nil, module: String? = nil,
        typeAnnotation: String? = nil,
        genericParameters: [String] = [], signature: FunctionSignature? = nil, source: Source
    ) {
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.isStatic = isStatic
        self.file = file
        self.line = line
        self.column = column
        self.containers = containers
        self.usr = usr
        self.module = module
        self.typeAnnotation = typeAnnotation
        self.genericParameters = genericParameters
        self.signature = signature
        self.source = source
    }

    /// A match for `declaration` of `file`.
    public init(_ declaration: Declaration, file: String) {
        self.init(
            name: declaration.name, kind: declaration.kind, accessLevel: declaration.accessLevel,
            isStatic: declaration.isStatic, file: file, line: declaration.line, column: declaration.column,
            containers: declaration.containers, typeAnnotation: declaration.typeAnnotation,
            genericParameters: declaration.genericParameters, signature: declaration.signature, source: .syntax)
    }

    /// The immediately enclosing type or extension.
    public var containingType: String? { containers.last }

    /// `Outer.Inner.name`.
    public var qualifiedName: String { (containers + [name]).joined(separator: ".") }

    /// `Outer.Inner.fetch(id:)` for a callable, `qualifiedName` otherwise.
    public var qualifiedSelector: String { qualifiedName + (signature?.selector ?? "") }

    /// `file:line:column`.
    public var location: String { "\(file):\(line):\(column)" }

    /// The same match with `usr` and `module` from the index store.
    public func with(usr: String?, module: String?) -> SymbolMatch {
        SymbolMatch(
            name: name, kind: kind, accessLevel: accessLevel, isStatic: isStatic, file: file, line: line,
            column: column, containers: containers, usr: usr ?? self.usr, module: module ?? self.module,
            typeAnnotation: typeAnnotation, genericParameters: genericParameters, signature: signature, source: source)
    }
}

extension SymbolMatch: Comparable {
    /// By file, line, then column.
    public static func < (lhs: SymbolMatch, rhs: SymbolMatch) -> Bool {
        (lhs.file, lhs.line, lhs.column) < (rhs.file, rhs.line, rhs.column)
    }
}
