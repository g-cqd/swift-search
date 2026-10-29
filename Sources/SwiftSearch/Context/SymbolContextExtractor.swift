internal import ProjectModel
internal import SourceCorpus
internal import SwiftParser
internal import SwiftSyntax

/// Reads what surrounds a declaration in its file: lines, signature, body, documentation and enclosing scope.
public enum SymbolContextExtractor {
    /// The context of the declaration whose name starts at `line` and `column` (1-based, UTF-8) of `file`.
    ///
    /// The file is read again, with analyzerkit's bounded reader, so the context is current even when the match came
    /// from a cache or an index. Nil when the file cannot be read, nests too deeply to walk, or has no declaration
    /// there (it changed since the match was made); the lines are still returned when only the declaration is missing.
    /// - Complexity: O(*n*) in the file's size.
    public static func context(file: String, line: Int, column: Int, options: SymbolContextOptions) async
        -> SymbolContext?
    {
        guard !options.isEmpty,
            let bytes = try? BoundedFileReader.read(path: file, cap: BoundedFileReader.sourceByteCap)
        else { return nil }
        let source = String(decoding: bytes, as: UTF8.self)
        // swift-syntax recurses once per level of the tree; the large stack is what analyzerkit's scan uses too.
        return await LargeStack.run {
            context(source: source, file: file, line: line, column: column, options: options)
        }
    }

    /// The context of the declaration at `line` and `column` of `source`, the text of `file`.
    public static func context(source: String, file: String, line: Int, column: Int, options: SymbolContextOptions)
        -> SymbolContext?
    {
        // `\r\n` is one Character; the compiler ends a line at `\n`, `\r\n` and `\r` alike.
        let sourceLines = source.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r\n" || $0 == "\r"
        }.map(String.init)
        guard line >= 1, line <= sourceLines.count else { return nil }
        var lines: [SymbolContext.Line] = []
        if options.linesBefore > 0 || options.linesAfter > 0 {
            let first = max(1, line - options.linesBefore)
            let last = min(sourceLines.count, line + options.linesAfter)
            lines = (first...last).map {
                SymbolContext.Line(number: $0, text: sourceLines[$0 - 1], isDeclaration: $0 == line)
            }
        }
        let tree = Parser.parse(source: source)
        guard !SyntaxDepth.exceeds(tree) else { return nil }
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let position = converter.position(ofLine: line, column: column)
        guard let token = tree.token(at: position), let declaration = enclosingDeclaration(of: Syntax(token)) else {
            return SymbolContext(
                lines: lines, signature: nil, body: nil, bodyIsTruncated: false, documentation: nil, scope: nil)
        }
        var signature: String?
        var body: String?
        var truncated = false
        let bodyNode = Self.body(of: declaration)
        if options.signature {
            let end = bodyNode?.positionAfterSkippingLeadingTrivia ?? declaration.endPositionBeforeTrailingTrivia
            signature = text(source, from: declaration.positionAfterSkippingLeadingTrivia, to: end)
        }
        if options.body, let bodyNode {
            let bodyLines = bodyNode.trimmedDescription.split(separator: "\n", omittingEmptySubsequences: false)
            truncated = bodyLines.count > SymbolContextOptions.maximumBodyLines
            body = bodyLines.prefix(SymbolContextOptions.maximumBodyLines).joined(separator: "\n")
        }
        return SymbolContext(
            lines: lines, signature: signature, body: body, bodyIsTruncated: truncated,
            documentation: options.documentation ? documentation(of: declaration) : nil,
            scope: options.scope ? scope(of: declaration, converter: converter) : nil)
    }

    // MARK: Syntax

    /// The declaration a name token belongs to: the nearest declaration or enum case element above it.
    private static func enclosingDeclaration(of node: Syntax) -> Syntax? {
        var current: Syntax? = node
        while let candidate = current {
            if candidate.is(EnumCaseElementSyntax.self) {
                return candidate.parent?.parent  // the EnumCaseDeclSyntax, which holds the documentation
            }
            if candidate.isProtocol((any DeclSyntaxProtocol).self) { return candidate }
            current = candidate.parent
        }
        return nil
    }

    private static func body(of declaration: Syntax) -> Syntax? {
        if let function = declaration.as(FunctionDeclSyntax.self) { return function.body.map(Syntax.init) }
        if let initializer = declaration.as(InitializerDeclSyntax.self) { return initializer.body.map(Syntax.init) }
        if let deinitializer = declaration.as(DeinitializerDeclSyntax.self) {
            return deinitializer.body.map(Syntax.init)
        }
        if let subscriptDecl = declaration.as(SubscriptDeclSyntax.self) {
            return subscriptDecl.accessorBlock.map(Syntax.init)
        }
        if let variable = declaration.as(VariableDeclSyntax.self) {
            return variable.bindings.last?.accessorBlock.map(Syntax.init)
        }
        if let group = declaration.asProtocol((any DeclGroupSyntax).self) { return Syntax(group.memberBlock) }
        return nil
    }

    private static func documentation(of declaration: Syntax) -> SymbolContext.Documentation? {
        var lines: [String] = []
        for piece in declaration.leadingTrivia {
            switch piece {
            case .docLineComment(let text):
                let line = text.dropFirst(3)
                lines.append(String(line.hasPrefix(" ") ? line.dropFirst() : line))
            case .docBlockComment(let text):
                let inner = text.dropFirst(3).dropLast(2)
                for line in inner.split(separator: "\n", omittingEmptySubsequences: false) {
                    var trimmed = String(line).trimmingWhitespace()
                    if trimmed.hasPrefix("*") { trimmed = String(trimmed.dropFirst()) }
                    lines.append(trimmed)
                }
            case .lineComment, .blockComment:
                // A plain comment between documentation and the declaration ends the documentation above it.
                lines.removeAll()
            default:
                continue
            }
        }
        return DocumentationParser.parse(lines)
    }

    private static func scope(of declaration: Syntax, converter: SourceLocationConverter) -> SymbolContext.Scope? {
        var current = declaration.parent
        while let node = current {
            if let named = scopeName(node) {
                return SymbolContext.Scope(
                    kind: named.kind, name: named.name,
                    startLine: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
                    endLine: converter.location(for: node.endPositionBeforeTrailingTrivia).line)
            }
            current = node.parent
        }
        return nil
    }

    private static func scopeName(_ node: Syntax) -> (kind: String, name: String)? {
        if let type = node.as(ClassDeclSyntax.self) { return ("class", type.name.text) }
        if let type = node.as(StructDeclSyntax.self) { return ("struct", type.name.text) }
        if let type = node.as(EnumDeclSyntax.self) { return ("enum", type.name.text) }
        if let type = node.as(ActorDeclSyntax.self) { return ("actor", type.name.text) }
        if let type = node.as(ProtocolDeclSyntax.self) { return ("protocol", type.name.text) }
        if let type = node.as(ExtensionDeclSyntax.self) { return ("extension", type.extendedType.trimmedDescription) }
        if let function = node.as(FunctionDeclSyntax.self) { return ("function", function.name.text) }
        if node.is(InitializerDeclSyntax.self) { return ("initializer", "init") }
        return nil
    }

    private static func text(_ source: String, from start: AbsolutePosition, to end: AbsolutePosition) -> String? {
        let utf8 = source.utf8
        guard start.utf8Offset <= end.utf8Offset, end.utf8Offset <= utf8.count else { return nil }
        let lower = utf8.index(utf8.startIndex, offsetBy: start.utf8Offset)
        let upper = utf8.index(utf8.startIndex, offsetBy: end.utf8Offset)
        let text = String(decoding: utf8[lower..<upper], as: UTF8.self).trimmingWhitespace()
        return text.isEmpty ? nil : text
    }
}
