internal import AemiRegex

/// A regular expression matched against whole symbol names, in linear time: no expression can make a search
/// exponential, so one from an MCP client is safe to run.
public struct NameExpression: Sendable {
    public let expression: String
    private let pattern: Pattern

    /// Compiles `expression` (RE2 syntax), anchored at both ends.
    /// - Throws: ``QueryParseError/invalidRegex(_:reason:)`` for malformed syntax, an unsupported construct
    ///   (backreferences, lookaround) or an expression over AemiRegex's limits.
    public init(_ expression: String) throws(QueryParseError) {
        self.expression = expression
        do {
            // Anchoring rather than `wholeMatch`: a leftmost-first match of `a|ab` on "ab" is "a", so testing the
            // first match's extent would miss a whole match an alternative gives.
            pattern = try Pattern("^(?:" + expression + ")$")
        } catch {
            throw .invalidRegex(expression, reason: String(describing: error))
        }
    }

    /// Whether the expression matches the whole of `name`.
    /// - Complexity: O(*m* · *n*) in the expression and name sizes.
    public func matches(_ name: String) -> Bool {
        pattern.firstMatch(in: name) != nil
    }
}
