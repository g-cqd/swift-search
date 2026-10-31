/// Answers queries from the syntax of the corpus: no build, no index, current to the bytes on disk.
public enum SyntaxResolver {
    /// The declarations of `table` that `pattern` names. A USR names nothing here: only the index store knows USRs.
    /// - Throws: ``QueryParseError/invalidRegex(_:reason:)`` for a regex that does not compile.
    /// - Complexity: O(*k*) in the declarations with the name; O(*n* · *m*) over every declaration for a regex.
    public static func resolve(_ pattern: SymbolQuery.Pattern, in table: SymbolTable) throws(QueryParseError)
        -> [SymbolMatch]
    {
        switch pattern {
        case .name(let name):
            return table.declarations(named: name).map(match)
        case .qualified(let types, let name):
            return table.declarations(named: name).filter { endsWith($0.declaration.containers, types) }.map(match)
        case .selector(let types, let name, let labels):
            return table.declarations(named: name).filter { entry in
                guard let signature = entry.declaration.signature else { return false }
                return signature.labels == labels && endsWith(entry.declaration.containers, types)
            }.map(match)
        case .usr:
            return []
        case .regex(let expression):
            let compiled = try NameExpression(expression)
            return table.entries.filter { compiled.matches($0.declaration.name) }.map(match)
        }
    }

    /// The references in `table` whose name is `match`'s name: every use of the name, not only those the compiler
    /// would resolve to `match`. A use through a written base (`Foo.bar`) is kept only when the base ends with
    /// `match`'s enclosing type, or names no type (`self.bar`, `value.bar`); a call only when its argument labels fit
    /// `match`'s parameters, and never for a property whose declared type is not a function.
    /// - Complexity: O(*k*) in the references with the name.
    public static func uses(of match: SymbolMatch, in table: SymbolTable) -> [Usage] {
        let container = match.containingType
        return table.uses(of: match.name).compactMap { use in
            let reference = use.reference
            if let base = reference.base, let container {
                let last = base.split(separator: ".").last.map(String.init) ?? base
                if table.typeNames.contains(last), last != container { return nil }
            }
            // The declaration's own name token is not a use.
            if use.file == match.file, reference.line == match.line, reference.column == match.column { return nil }
            // A call whose labels the declaration cannot take calls another overload or another function.
            if let signature = match.signature,
                !reference.canCall(signature, unlabeledFitsAny: match.kind == .enumCase)
            {
                return nil
            }
            // A property declared with a type that is not a function cannot be called.
            if reference.role == .call, match.kind == .variable || match.kind == .constant,
                let type = match.typeAnnotation, !type.contains("->")
            {
                return nil
            }
            return Usage(
                file: use.file, line: reference.line, column: reference.column, role: role(reference.role),
                symbol: match.qualifiedSelector, isResolved: false)
        }
    }

    private static func match(_ entry: SymbolTable.Entry) -> SymbolMatch {
        SymbolMatch(entry.declaration, file: entry.file)
    }

    /// Whether `containers` ends with `suffix`: `Inner.member` names a member of `Outer.Inner`.
    private static func endsWith(_ containers: [String], _ suffix: [String]) -> Bool {
        containers.count >= suffix.count && Array(containers.suffix(suffix.count)) == suffix
    }

    private static func role(_ role: Reference.Role) -> Usage.Role {
        switch role {
        case .call: .call
        case .read: .read
        case .write: .write
        case .type: .type
        }
    }
}
