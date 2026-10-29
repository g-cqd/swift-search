/// What surrounds a declaration in its file.
public struct SymbolContext: Sendable, Codable, Equatable {
    /// One numbered line of source.
    public struct Line: Sendable, Codable, Equatable {
        public let number: Int
        public let text: String
        /// Whether this is the line the declaration's name is on.
        public let isDeclaration: Bool
    }

    /// The declaration or extension that encloses another.
    public struct Scope: Sendable, Codable, Equatable {
        public let kind: String
        public let name: String
        public let startLine: Int
        public let endLine: Int
    }

    /// The parts of a documentation comment.
    public struct Documentation: Sendable, Codable, Equatable {
        public let summary: String?
        public let parameters: [String: String]
        public let returns: String?
        public let `throws`: String?
        /// The comment without its markers, line by line.
        public let text: String
    }

    /// The lines around the declaration, its own line included; empty unless asked for.
    public let lines: [Line]
    /// The declaration up to its body: attributes, modifiers, name, generics, parameters, effects, result.
    public let signature: String?
    /// The body or member block; cut at ``SymbolContextOptions/maximumBodyLines``.
    public let body: String?
    public let bodyIsTruncated: Bool
    public let documentation: Documentation?
    public let scope: Scope?
}

/// Which parts of a ``SymbolContext`` to extract.
public struct SymbolContextOptions: Sendable, Equatable {
    /// The most body lines returned; a longer body is cut and marked truncated.
    public static let maximumBodyLines = 400
    /// The most lines of context on either side.
    public static let maximumContextLines = 200

    public var linesBefore: Int
    public var linesAfter: Int
    public var signature: Bool
    public var body: Bool
    public var documentation: Bool
    public var scope: Bool

    public init(
        linesBefore: Int = 0, linesAfter: Int = 0, signature: Bool = false, body: Bool = false,
        documentation: Bool = false, scope: Bool = false
    ) {
        self.linesBefore = min(max(linesBefore, 0), Self.maximumContextLines)
        self.linesAfter = min(max(linesAfter, 0), Self.maximumContextLines)
        self.signature = signature
        self.body = body
        self.documentation = documentation
        self.scope = scope
    }

    /// Five lines either side, the signature, the body, the documentation and the scope.
    public static let all = SymbolContextOptions(
        linesBefore: 5, linesAfter: 5, signature: true, body: true, documentation: true, scope: true)

    /// Whether any part is asked for.
    public var isEmpty: Bool {
        linesBefore == 0 && linesAfter == 0 && !signature && !body && !documentation && !scope
    }
}
