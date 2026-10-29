/// One declaration of a source file, as the syntax gives it.
public struct Declaration: Sendable, Hashable, Codable {
    public let name: String
    public let kind: DeclarationKind
    /// The written access level, or the one the enclosing extension or protocol gives; `internal` otherwise.
    public let accessLevel: AccessLevel
    public let isStatic: Bool
    /// The 1-based line of the name.
    public let line: Int
    /// The 1-based UTF-8 column of the name.
    public let column: Int
    /// The 1-based line the declaration ends on.
    public let endLine: Int
    /// The enclosing types and extensions, outermost first: `["Outer", "Inner"]`. An extension contributes the type it
    /// extends, as written.
    public let containers: [String]
    /// The declared type of a variable or constant, as written.
    public let typeAnnotation: String?
    public let genericParameters: [String]
    public let signature: FunctionSignature?

    public init(
        name: String, kind: DeclarationKind, accessLevel: AccessLevel, isStatic: Bool, line: Int, column: Int,
        endLine: Int, containers: [String], typeAnnotation: String? = nil, genericParameters: [String] = [],
        signature: FunctionSignature? = nil
    ) {
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.isStatic = isStatic
        self.line = line
        self.column = column
        self.endLine = endLine
        self.containers = containers
        self.typeAnnotation = typeAnnotation
        self.genericParameters = genericParameters
        self.signature = signature
    }
}
