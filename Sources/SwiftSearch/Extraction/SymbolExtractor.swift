internal import ProjectModel
internal import SwiftParser
internal import SwiftSyntax

/// Reads the declarations and references of one source file.
///
/// Declarations at file and type scope are recorded; those inside a function, accessor or closure body (locals) are
/// not, since no other file can name them. References are recorded everywhere.
public enum SymbolExtractor {
    /// The symbols of `bytes`, the UTF-8 text of the file at `path`. Invalid UTF-8 is replaced, not rejected.
    /// - Complexity: O(*n*) in the source size.
    public static func extract(bytes: [UInt8], path: String) -> FileSymbols {
        extract(source: String(decoding: bytes, as: UTF8.self), path: path)
    }

    /// The symbols of `source`, the text of the file at `path`.
    ///
    /// A tree nested deeper than analyzerkit's `SyntaxDepth.defaultLimit` is not walked: the visitor recurses once per
    /// level. Such a file is returned with ``FileSymbols/degraded`` set.
    /// - Complexity: O(*n*) in the source size.
    public static func extract(source: String, path: String) -> FileSymbols {
        let tree = Parser.parse(source: source)
        if SyntaxDepth.exceeds(tree) {
            return FileSymbols(
                path: path, declarations: [], references: [],
                degraded: "nested deeper than \(SyntaxDepth.defaultLimit) levels; not read for symbols")
        }
        let visitor = SymbolVisitor(converter: SourceLocationConverter(fileName: path, tree: tree))
        visitor.walk(tree)
        return FileSymbols(path: path, declarations: visitor.declarations, references: visitor.references)
    }
}

/// The walk behind ``SymbolExtractor``.
final class SymbolVisitor: SyntaxVisitor {
    private struct Container {
        let names: [String]
        /// The access level the container gives its members when they write none: an extension's or a protocol's.
        let memberAccess: AccessLevel?
    }

    /// The longest member-access base kept, in UTF-8 bytes; a longer one is an expression, not a type name.
    private static let maximumBaseLength = 256

    private let converter: SourceLocationConverter
    private var containers: [Container] = []
    /// Bodies entered: a declaration inside one is local.
    private var bodyDepth = 0
    private(set) var declarations: [Declaration] = []
    private(set) var references: [Reference] = []

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Types

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        openType(.class, name: node.name, node: node, modifiers: node.modifiers, generics: node.genericParameterClause)
    }
    override func visitPost(_ node: ClassDeclSyntax) { closeType() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        openType(.struct, name: node.name, node: node, modifiers: node.modifiers, generics: node.genericParameterClause)
    }
    override func visitPost(_ node: StructDeclSyntax) { closeType() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        openType(.enum, name: node.name, node: node, modifiers: node.modifiers, generics: node.genericParameterClause)
    }
    override func visitPost(_ node: EnumDeclSyntax) { closeType() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        openType(.actor, name: node.name, node: node, modifiers: node.modifiers, generics: node.genericParameterClause)
    }
    override func visitPost(_ node: ActorDeclSyntax) { closeType() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = accessLevel(node.modifiers)
        guard bodyDepth == 0 else {
            containers.append(Container(names: [node.name.text], memberAccess: nil))
            return .visitChildren
        }
        record(node.name.text, .protocol, node: node, name: node.name, modifiers: node.modifiers)
        containers.append(Container(names: [node.name.text], memberAccess: access ?? inheritedAccess))
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { closeType() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let path = Self.typePath(node.extendedType)
        if bodyDepth == 0, let last = path.last {
            record(
                last, .extension, node: node, name: node.extendedType, modifiers: node.modifiers,
                extraContainers: Array(path.dropLast()))
        }
        containers.append(Container(names: path, memberAccess: accessLevel(node.modifiers)))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { closeType() }

    // MARK: Members

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(
                node.name.text, containers.isEmpty ? .function : .method, node: node, name: node.name,
                modifiers: node.modifiers, generics: node.genericParameterClause,
                signature: signature(
                    node.signature.parameterClause, returns: node.signature.returnClause,
                    effects: node.signature.effectSpecifiers))
        }
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { bodyDepth -= 1 }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(
                "init", .initializer, node: node, name: node.initKeyword, modifiers: node.modifiers,
                generics: node.genericParameterClause,
                signature: signature(
                    node.signature.parameterClause, returns: nil, effects: node.signature.effectSpecifiers))
        }
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: InitializerDeclSyntax) { bodyDepth -= 1 }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record("deinit", .deinitializer, node: node, name: node.deinitKeyword, modifiers: node.modifiers)
        }
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: DeinitializerDeclSyntax) { bodyDepth -= 1 }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(
                "subscript", .subscript, node: node, name: node.subscriptKeyword, modifiers: node.modifiers,
                generics: node.genericParameterClause,
                signature: signature(node.parameterClause, returns: node.returnClause, effects: nil))
        }
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: SubscriptDeclSyntax) { bodyDepth -= 1 }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard bodyDepth == 0 else { return .visitChildren }
        let kind: DeclarationKind = node.bindingSpecifier.tokenKind == .keyword(.let) ? .constant : .variable
        for binding in node.bindings {
            for identifier in Self.identifiers(in: binding.pattern) {
                record(
                    identifier.text, kind, node: node, name: identifier, modifiers: node.modifiers,
                    typeAnnotation: binding.typeAnnotation?.type.trimmedDescription)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        guard bodyDepth == 0, let declaration = node.parent?.parent?.as(EnumCaseDeclSyntax.self) else {
            return .visitChildren
        }
        record(
            node.name.text, .enumCase, node: node, name: node.name, modifiers: declaration.modifiers,
            signature: node.parameterClause.map(signature))
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(
                node.name.text, .typealias, node: node, name: node.name, modifiers: node.modifiers,
                generics: node.genericParameterClause)
        }
        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(node.name.text, .associatedtype, node: node, name: node.name, modifiers: node.modifiers)
        }
        return .visitChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(
                node.name.text, .macro, node: node, name: node.name, modifiers: node.modifiers,
                generics: node.genericParameterClause,
                signature: signature(node.signature.parameterClause, returns: node.signature.returnClause, effects: nil)
            )
        }
        return .skipChildren
    }

    override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 { record(node.name.text, .operator, node: node, name: node.name, modifiers: nil) }
        return .skipChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.path.map(\.name.text).joined(separator: ".")
        record(name, .import, node: node, name: node.path, modifiers: node.modifiers)
        return .skipChildren
    }

    // MARK: Bodies

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: AccessorBlockSyntax) { bodyDepth -= 1 }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        bodyDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: ClosureExprSyntax) { bodyDepth -= 1 }

    // MARK: References

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        guard !name.isEmpty, name != "self", name != "Self", name != "super" else { return .visitChildren }
        var expression = Syntax(node)
        var base: String?
        var subjectType: String?
        var subjectPath: [Reference.PatternStep] = []
        if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
            expression = Syntax(member)
            base = member.base.flatMap(Self.baseName)
            if member.base == nil, let pattern = Self.patternSubject(of: member) {
                subjectPath = pattern.path
                switch pattern.subject {
                case .expression(let subject): subjectType = self.type(of: subject)
                case .type(let type): subjectType = type
                }
            }
        }
        let location = converter.location(for: node.baseName.positionAfterSkippingLeadingTrivia)
        let role = Self.role(of: expression)
        let arguments = role == .call ? expression.parent?.as(FunctionCallExprSyntax.self)?.arguments : nil
        references.append(
            Reference(
                name: name, line: location.line, column: location.column, role: role, base: base,
                arguments: arguments.map { $0.map { $0.label?.text } }, subjectType: subjectType,
                subjectPath: subjectPath))
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        appendTypeReference(node.name, base: nil)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        appendTypeReference(node.name, base: Self.typePath(node.baseType).joined(separator: "."))
        return .visitChildren
    }

    // MARK: Recording

    private var inheritedAccess: AccessLevel? { containers.last?.memberAccess }

    private func openType(
        _ kind: DeclarationKind, name: TokenSyntax, node: some DeclSyntaxProtocol, modifiers: DeclModifierListSyntax,
        generics: GenericParameterClauseSyntax?
    ) -> SyntaxVisitorContinueKind {
        if bodyDepth == 0 {
            record(name.text, kind, node: node, name: name, modifiers: modifiers, generics: generics)
        }
        containers.append(Container(names: [name.text], memberAccess: nil))
        return .visitChildren
    }

    private func closeType() {
        _ = containers.popLast()
    }

    private func record(
        _ text: String, _ kind: DeclarationKind, node: some SyntaxProtocol, name: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax?, generics: GenericParameterClauseSyntax? = nil,
        signature: FunctionSignature? = nil, typeAnnotation: String? = nil, extraContainers: [String] = []
    ) {
        guard !text.isEmpty else { return }
        let start = converter.location(for: name.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        let written = modifiers.flatMap(accessLevel)
        let isStatic =
            modifiers?.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
            ?? false
        declarations.append(
            Declaration(
                name: text, kind: kind, accessLevel: written ?? inheritedAccess ?? .internal, isStatic: isStatic,
                line: start.line, column: start.column, endLine: end.line,
                containers: containers.flatMap(\.names) + extraContainers, typeAnnotation: typeAnnotation,
                genericParameters: generics?.parameters.map(\.name.text) ?? [], signature: signature))
    }

    private func appendTypeReference(_ name: TokenSyntax, base: String?) {
        let text = name.text
        guard !text.isEmpty, text != "Self", text != "Any" else { return }
        let location = converter.location(for: name.positionAfterSkippingLeadingTrivia)
        references.append(
            Reference(
                name: text, line: location.line, column: location.column, role: .type,
                base: base.flatMap { $0.isEmpty ? nil : $0 }))
    }

    private func accessLevel(_ modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers where modifier.detail == nil {
            switch modifier.name.tokenKind {
            case .keyword(.private): return .private
            case .keyword(.fileprivate): return .fileprivate
            case .keyword(.internal): return .internal
            case .keyword(.package): return .package
            case .keyword(.public): return .public
            case .keyword(.open): return .open
            default: continue
            }
        }
        return nil
    }

    private func signature(
        _ clause: FunctionParameterClauseSyntax, returns: ReturnClauseSyntax?,
        effects: FunctionEffectSpecifiersSyntax?
    ) -> FunctionSignature {
        FunctionSignature(
            parameters: clause.parameters.map { parameter in
                let label = parameter.firstName.text
                return FunctionSignature.Parameter(
                    label: label == "_" ? nil : label, name: parameter.secondName?.text ?? label,
                    type: parameter.type.trimmedDescription + (parameter.ellipsis == nil ? "" : "..."))
            },
            returnType: returns?.type.trimmedDescription, isAsync: effects?.asyncSpecifier != nil,
            isThrowing: effects?.throwsClause != nil)
    }

    /// The associated values of an enum case as parameters: `case moved(to: Int, _ by: Int)` takes `(to:_:)`.
    private func signature(_ clause: EnumCaseParameterClauseSyntax) -> FunctionSignature {
        FunctionSignature(
            parameters: clause.parameters.map { parameter in
                let label = parameter.firstName.map(\.text).flatMap { $0 == "_" ? nil : $0 }
                return FunctionSignature.Parameter(
                    label: label, name: parameter.secondName?.text ?? label ?? "_",
                    type: parameter.type.trimmedDescription)
            })
    }

    // MARK: Syntax helpers

    /// `Outer.Inner<T>` as `["Outer", "Inner"]`.
    private static func typePath(_ type: TypeSyntax) -> [String] {
        var names: [String] = []
        var current: TypeSyntax? = type
        // A member type nests leftward, one level per component: a loop, not recursion.
        while let node = current {
            if let member = node.as(MemberTypeSyntax.self) {
                names.append(member.name.text)
                current = member.baseType
            } else if let identifier = node.as(IdentifierTypeSyntax.self) {
                names.append(identifier.name.text)
                current = nil
            } else {
                names.append(node.trimmedDescription)
                current = nil
            }
        }
        return names.reversed()
    }

    /// The identifiers a binding pattern introduces: `a` in `a`, `a` and `b` in `(a, b)`.
    private static func identifiers(in pattern: PatternSyntax) -> [TokenSyntax] {
        var found: [TokenSyntax] = []
        var pending: [PatternSyntax] = [pattern]
        while let next = pending.popLast() {
            if let identifier = next.as(IdentifierPatternSyntax.self) {
                found.append(identifier.identifier)
            } else if let tuple = next.as(TuplePatternSyntax.self) {
                pending += tuple.elements.reversed().map(\.pattern)
            }
        }
        return found
    }

    /// The written base of a member access when it names something (`Foo`, `Foo.Bar`, `self.foo`), the callee of a call
    /// base (`Foo` for `Foo()`, `Foo.make` for `Foo.make(x)`), nil for any other expression.
    private static func baseName(_ base: ExprSyntax) -> String? {
        let named = base.as(FunctionCallExprSyntax.self)?.calledExpression ?? base
        let text = named.trimmedDescription
        guard text.utf8.count <= maximumBaseLength,
            text.utf8.allSatisfy({
                $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "_") || $0 >= 0x80 || isAlphanumeric($0)
            })
        else { return nil }
        return text
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// What a pattern is matched against: an expression, or a type the syntax names outright.
    private enum PatternSubject {
        case expression(ExprSyntax)
        case type(String)
    }

    /// The subject of the pattern a leading-dot member is part of, alone or called (`.moved(let to)`), and the enum
    /// case patterns it is nested in (`.recording(.moved(let to))`), outermost first. The pattern is a `switch` case's,
    /// an `if`, `guard` or `while case`'s, or a `catch`'s, whose subject is the type its `do throws(T)` names. An
    /// outer case written with its type (`Wrapper.recording(…)`) gives that type. Nil for any other place, a tuple
    /// pattern for example.
    private static func patternSubject(of member: MemberAccessExprSyntax)
        -> (subject: PatternSubject, path: [Reference.PatternStep])?
    {
        var path: [Reference.PatternStep] = []
        var node = Syntax(member)
        // Each enclosing case pattern is one step out: a loop, not recursion.
        while true {
            if let call = node.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id {
                node = Syntax(call)
            }
            if let chaining = node.parent?.as(OptionalChainingExprSyntax.self) { node = Syntax(chaining) }
            guard let argument = node.parent?.as(LabeledExprSyntax.self),
                let list = argument.parent?.as(LabeledExprListSyntax.self),
                let call = list.parent?.as(FunctionCallExprSyntax.self),
                let outer = call.calledExpression.as(MemberAccessExprSyntax.self)
            else { break }
            let index = list.firstIndex { $0.id == argument.id }.map { list.distance(from: list.startIndex, to: $0) }
            guard let index else { return nil }
            path.insert(Reference.PatternStep(caseName: outer.declName.baseName.text, argument: index), at: 0)
            if let written = outer.base {
                guard let type = baseName(written)?.split(separator: ".").last.map(String.init),
                    isInPattern(Syntax(call))
                else { return nil }
                return (.type(type), path)
            }
            node = Syntax(outer)
        }
        guard var pattern = node.parent?.as(ExpressionPatternSyntax.self).map(Syntax.init) else { return nil }
        while let binding = pattern.parent?.as(ValueBindingPatternSyntax.self) { pattern = Syntax(binding) }
        if let condition = pattern.parent?.as(MatchingPatternConditionSyntax.self) {
            return (.expression(condition.initializer.value), path)
        }
        if pattern.parent?.is(CatchItemSyntax.self) == true {
            var ancestor = pattern.parent
            while let current = ancestor, !current.is(DoStmtSyntax.self) { ancestor = current.parent }
            guard let type = ancestor?.as(DoStmtSyntax.self)?.throwsClause?.type, let name = typeName(type) else {
                return nil
            }
            return (.type(name), path)
        }
        guard pattern.parent?.is(SwitchCaseItemSyntax.self) == true else { return nil }
        var ancestor = pattern.parent
        while let current = ancestor, !current.is(SwitchExprSyntax.self) { ancestor = current.parent }
        guard let statement = ancestor?.as(SwitchExprSyntax.self) else { return nil }
        return (.expression(statement.subject), path)
    }

    /// Whether `node` (an expression) is, through calls and arguments, an expression pattern.
    private static func isInPattern(_ node: Syntax) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(ExpressionPatternSyntax.self) { return true }
            if current.is(CodeBlockItemSyntax.self) || current.is(MemberBlockItemSyntax.self) { return false }
            ancestor = current.parent
        }
        return false
    }

    /// The type of `subject` as the syntax gives it: the enclosing type for `self`, and for a parameter of the
    /// enclosing function, initializer or subscript, the last name of its declared type, an optional's wrapped one.
    /// A closure between the two may rebind the name, so its parameters stop the search.
    private func type(of subject: ExprSyntax) -> String? {
        guard let reference = subject.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = reference.baseName.text
        if name == "self" { return containers.last?.names.last }
        var ancestor = subject.parent
        while let node = ancestor {
            if node.is(ClosureExprSyntax.self) { return nil }
            let parameters: FunctionParameterListSyntax? =
                node.as(FunctionDeclSyntax.self)?.signature.parameterClause.parameters
                ?? node.as(InitializerDeclSyntax.self)?.signature.parameterClause.parameters
                ?? node.as(SubscriptDeclSyntax.self)?.parameterClause.parameters
            if let parameters {
                let parameter = parameters.first { ($0.secondName ?? $0.firstName).text == name }
                return parameter.flatMap { Self.typeName($0.type) }
            }
            ancestor = node.parent
        }
        return nil
    }

    /// `Outer.Inner` as `Inner`, `Value?` as `Value`; nil for a type with no single name (a tuple, a function).
    private static func typeName(_ type: TypeSyntax) -> String? {
        var type = type
        // Each wrapper peels one level: a loop, not recursion.
        while true {
            if let optional = type.as(OptionalTypeSyntax.self) {
                type = optional.wrappedType
            } else if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                type = unwrapped.wrappedType
            } else if let attributed = type.as(AttributedTypeSyntax.self) {
                type = attributed.baseType
            } else {
                return type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) ? typePath(type).last : nil
            }
        }
    }

    /// How the expression `node` (a name, or a member access) is used by its parent.
    private static func role(of node: Syntax) -> Reference.Role {
        guard let parent = node.parent else { return .read }
        if let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == node.id { return .call }
        if parent.is(InOutExprSyntax.self) { return .write }
        if let list = parent.as(ExprListSyntax.self) {
            var iterator = list.makeIterator()
            while let element = iterator.next() {
                guard element.id == node.id else { continue }
                if let next = iterator.next(), isAssignment(next) { return .write }
                break
            }
        }
        return .read
    }

    /// `=` or a compound assignment such as `+=`, in an unfolded sequence.
    private static func isAssignment(_ expression: ExprSyntax) -> Bool {
        if expression.is(AssignmentExprSyntax.self) { return true }
        guard let binary = expression.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "===", "!=="].contains(text)
    }
}
