/// The parameters and effects of a function, method, initializer or subscript.
public struct FunctionSignature: Sendable, Hashable, Codable {
    /// One parameter.
    public struct Parameter: Sendable, Hashable, Codable {
        /// The argument label; nil for `_`.
        public let label: String?
        /// The name inside the body.
        public let name: String
        /// The type as written.
        public let type: String

        public init(label: String?, name: String, type: String) {
            self.label = label
            self.name = name
            self.type = type
        }
    }

    public let parameters: [Parameter]
    /// The return type as written; nil when none is written.
    public let returnType: String?
    public let isAsync: Bool
    public let isThrowing: Bool

    public init(parameters: [Parameter], returnType: String? = nil, isAsync: Bool = false, isThrowing: Bool = false) {
        self.parameters = parameters
        self.returnType = returnType
        self.isAsync = isAsync
        self.isThrowing = isThrowing
    }

    /// The labels of the selector, `nil` for `_`.
    public var labels: [String?] { parameters.map(\.label) }

    /// `(id:_:)`: the selector part of a name, as the compiler's index spells it.
    public var selector: String {
        "(" + parameters.map { ($0.label ?? "_") + ":" }.joined() + ")"
    }

    /// `(id: Int, _ name: String) async throws -> Data`.
    public var display: String {
        var text =
            "("
            + parameters.map { parameter in
                let head: String
                switch parameter.label {
                case nil: head = "_ " + parameter.name
                case parameter.name?: head = parameter.name
                case let label?: head = label + " " + parameter.name
                }
                return head + ": " + parameter.type
            }.joined(separator: ", ") + ")"
        if isAsync { text += " async" }
        if isThrowing { text += " throws" }
        if let returnType, returnType != "Void", returnType != "()" { text += " -> " + returnType }
        return text
    }
}
