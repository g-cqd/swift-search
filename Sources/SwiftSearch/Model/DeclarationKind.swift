/// What a declaration declares.
public enum DeclarationKind: String, Sendable, Codable, CaseIterable, Hashable {
    case function
    case method
    case initializer
    case deinitializer
    case variable
    case constant
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case `typealias`
    case `associatedtype`
    case `import`
    case `subscript`
    case `operator`
    case enumCase
    case actor
    case macro

    /// Whether the declaration introduces a type.
    public var isType: Bool {
        switch self {
        case .class, .struct, .enum, .protocol, .actor, .typealias, .associatedtype: true
        default: false
        }
    }
}
