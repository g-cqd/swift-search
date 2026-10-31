/// One use of a name in a source file, as the syntax gives it: not resolved to a declaration.
public struct Reference: Sendable, Hashable, Codable {
    /// How the name is used.
    public enum Role: String, Sendable, Hashable, Codable {
        case call
        case read
        case write
        case type
    }

    public let name: String
    public let line: Int
    /// The 1-based UTF-8 column.
    public let column: Int
    public let role: Role
    /// The base of a member access as written, `Foo` in `Foo.bar`; nil for a bare name or an expression base.
    public let base: String?
    /// The argument labels of a call, `nil` for an unlabeled argument; nil when the use is not a call. A trailing
    /// closure is not listed.
    public let arguments: [String?]?

    public init(name: String, line: Int, column: Int, role: Role, base: String? = nil, arguments: [String?]? = nil) {
        self.name = name
        self.line = line
        self.column = column
        self.role = role
        self.base = base
        self.arguments = arguments
    }

    /// Whether a call with these arguments can call a function with `signature`: each label, in order, is the label
    /// of a parameter, a parameter left out has a default (which the syntax of a use cannot see, so any may be left
    /// out), and a variadic parameter takes a run of unlabeled arguments after its own.
    ///
    /// With `unlabeledFitsAny`, an argument without a label fits any parameter: a pattern of an enum case may leave out
    /// the labels of its associated values (`case .moved(let to)`), or bind them all at once (`case .moved(let all)`).
    /// - Complexity: O(*a* + *p*) in the arguments and parameters.
    public func canCall(_ signature: FunctionSignature, unlabeledFitsAny: Bool = false) -> Bool {
        guard let arguments else { return true }
        var parameter = 0
        var index = 0
        while index < arguments.count {
            let label = arguments[index]
            while parameter < signature.parameters.count, !(label == nil && unlabeledFitsAny),
                signature.parameters[parameter].label != label
            {
                parameter += 1
            }
            guard parameter < signature.parameters.count else { return false }
            index += 1
            if signature.parameters[parameter].type.hasSuffix("...") {
                while index < arguments.count, arguments[index] == nil { index += 1 }
            }
            parameter += 1
        }
        return true
    }
}
