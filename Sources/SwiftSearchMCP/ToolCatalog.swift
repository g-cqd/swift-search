internal import AemiJSON
internal import SwiftSearch

/// The tools the server lists, with their input schemas.
enum ToolCatalog {
    static let search = "search_symbols"
    static let usages = "find_usages"
    static let workspaceSymbols = "lsp_workspace_symbols"
    static let definition = "lsp_definition"
    static let references = "lsp_references"
    static let implementations = "lsp_implementations"
    static let hover = "lsp_hover"
    static let callers = "lsp_callers"
    static let callees = "lsp_callees"

    /// The tools that ask sourcekit-lsp about one position.
    static let positionTools = [definition, references, implementations, hover, callers, callees]

    static var tools: JSONValue {
        .array(
            [
                tool(
                    search,
                    """
                    Find Swift declarations by name in the source files, without a build. The query is a name (shared), \
                    a qualified name (Client.shared, Outer.Inner.member), a selector (fetch(id:_:), Client.fetch(id:)), \
                    a regex over whole names (/load.*/, RE2 syntax), or a USR (s:...; needs index_store). Returns each \
                    declaration's symbol, kind, access, location (path:line:column, UTF-8 column, relative to the root \
                    when inside it), signature, and the context asked for.
                    """,
                    properties: queryProperties.merging(contextProperties) { first, _ in first }, required: ["query"]),
                tool(
                    usages,
                    """
                    Find where the declarations a query names are used. With index_store, only the uses the compiler \
                    resolved to them (resolved: true), from a build's index store; without it, every use of the name \
                    (resolved: false) except through a base that names another type.
                    """,
                    properties: queryProperties, required: ["query"]),
                tool(
                    workspaceSymbols,
                    "Ask sourcekit-lsp for the symbols matching a query (its fuzzy match), across the workspace's index.",
                    properties: [
                        "query": property("string", "The text to match."), "workspace": workspaceProperty,
                    ], required: ["query"]),
                positionTool(definition, "Ask sourcekit-lsp where the symbol is declared."),
                positionTool(references, "Ask sourcekit-lsp for every reference to the symbol, from its index."),
                positionTool(
                    implementations,
                    "Ask sourcekit-lsp for the implementations of a protocol requirement or the "
                        + "overrides of a member."),
                positionTool(hover, "Ask sourcekit-lsp for the declaration and documentation of the symbol."),
                positionTool(callers, "Ask sourcekit-lsp which functions call the function, and where."),
                positionTool(callees, "Ask sourcekit-lsp which functions the function calls, and where."),
            ])
    }

    private static let workspaceProperty = property(
        "string",
        "The directory sourcekit-lsp opens: a package root, or one with compile_commands.json. Default: the project "
            + "around the file, else the server's root.")

    private static let queryProperties: [String: JSONValue] = [
        "query": property("string", "Name, Type.member, selector f(x:), /regex/, or USR."),
        "paths": [
            "type": "array", "items": ["type": "string"],
            "description": "Files or directories to search, relative to the root. Default: the root.",
        ],
        "exclude": [
            "type": "array", "items": ["type": "string"], "description": "Paths to leave out: substrings or globs.",
        ],
        "kind": [
            "type": "array",
            "items": ["type": "string", "enum": .array(DeclarationKind.allCases.map { .string($0.rawValue) })],
            "description": "Only these declaration kinds.",
        ],
        "access": [
            "type": "array",
            "items": ["type": "string", "enum": .array(AccessLevel.allCases.map { .string($0.rawValue) })],
            "description": "Only these access levels.",
        ],
        "in_type": property("string", "Only members whose enclosing type or extension has this name."),
        "limit": property("integer", "At most this many results (default 100, at most 2000)."),
        "index_store": property(
            "boolean", "Read the compiler's index store found for the project (USRs, resolved uses)."),
        "index_store_path": property("string", "The index store to read; implies index_store."),
    ]

    private static let contextProperties: [String: JSONValue] = [
        "context_lines": property("integer", "Lines of source before and after each declaration (at most 200)."),
        "signature": property("boolean", "Include each declaration up to its body."),
        "body": property("boolean", "Include each body (at most 400 lines)."),
        "documentation": property("boolean", "Include each documentation comment, parsed."),
        "scope": property("boolean", "Include the enclosing type or function and its lines."),
    ]

    private static func positionTool(_ name: String, _ description: String) -> JSONValue {
        tool(
            name,
            description
                + " Name the symbol by file, line and column (1-based, UTF-8 column), or by symbol: a query as "
                + "search_symbols reads it that names exactly one declaration.",
            properties: [
                "file": property("string", "The file, relative to the root."),
                "line": property("integer", "1-based line."),
                "column": property("integer", "1-based UTF-8 column of the name."),
                "symbol": property("string", "A query naming one declaration instead of file/line/column."),
                "workspace": workspaceProperty,
            ], required: [])
    }

    private static func tool(_ name: String, _ description: String, properties: [String: JSONValue], required: [String])
        -> JSONValue
    {
        var members: [(String, JSONValue)] = [("type", "object")]
        var ordered: [(String, JSONValue)] = []
        for key in properties.keys.sorted() { ordered.append((key, properties[key] ?? .null)) }
        members.append(("properties", .makeObject { for member in ordered { member } }))
        if !required.isEmpty { members.append(("required", .array(required.map { .string($0) }))) }
        return [
            "name": .string(name), "description": .string(description),
            "inputSchema": .makeObject { for member in members { member } },
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ]
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        ["type": .string(type), "description": .string(description)]
    }
}
