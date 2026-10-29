/// A symbol lookup: a pattern and the filters its matches must pass.
public struct SymbolQuery: Sendable, Hashable {
    /// What names a query looks for.
    public enum Pattern: Sendable, Hashable {
        /// `shared`: every declaration with this name.
        case name(String)
        /// `Outer.Inner.member`: a member whose enclosing types end with these, outermost first.
        case qualified(types: [String], name: String)
        /// `fetch(id:_:)`, optionally `Type.fetch(id:)`: a callable with exactly these labels (`nil` for `_`).
        case selector(types: [String], name: String, labels: [String?])
        /// `s:4main3FooV`: the declaration the index store knows by this USR.
        case usr(String)
        /// `/Network.*/`: every declaration whose whole name the expression matches.
        case regex(String)

        /// The name the pattern looks for; the expression for a regex, the USR for a USR.
        public var name: String {
            switch self {
            case .name(let name), .qualified(_, let name), .selector(_, let name, _): name
            case .usr(let usr): usr
            case .regex(let expression): expression
            }
        }
    }

    public let pattern: Pattern
    /// Only these kinds; nil for every kind.
    public let kinds: Set<DeclarationKind>?
    /// Only these access levels; nil for every level.
    public let accessLevels: Set<AccessLevel>?
    /// Only members whose immediately enclosing type or extension has this name.
    public let containingType: String?
    /// At most this many matches, after sorting; nil for all.
    public let limit: Int?

    public init(
        pattern: Pattern, kinds: Set<DeclarationKind>? = nil, accessLevels: Set<AccessLevel>? = nil,
        containingType: String? = nil, limit: Int? = nil
    ) {
        self.pattern = pattern
        self.kinds = kinds.flatMap { $0.isEmpty ? nil : $0 }
        self.accessLevels = accessLevels.flatMap { $0.isEmpty ? nil : $0 }
        self.containingType = containingType
        self.limit = limit
    }

    /// Whether `match` passes the filters; the pattern is not checked.
    public func admits(_ match: SymbolMatch) -> Bool {
        if let kinds, !kinds.contains(match.kind) { return false }
        if let accessLevels, !accessLevels.contains(match.accessLevel) { return false }
        if let containingType, match.containingType != containingType { return false }
        return true
    }
}
