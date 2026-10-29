/// A declaration's access level, ordered from the most to the least restrictive.
public enum AccessLevel: String, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int {
        switch self {
        case .private: 0
        case .fileprivate: 1
        case .internal: 2
        case .package: 3
        case .public: 4
        case .open: 5
        }
    }
}
