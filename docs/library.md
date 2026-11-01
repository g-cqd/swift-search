# Using it as a library

| Product | Holds |
| --- | --- |
| `SwiftSearch` | The query language, per-file symbol facts, the syntax and index-store resolvers, usages, context. |
| `SwiftSearchLSP` | A JSON-RPC client of sourcekit-lsp. |
| `SwiftSearchMCP` | The MCP server and its stdio transport. |

```swift
let workspace = try await SearchWorkspace.open(.init(paths: ["Sources"], indexStore: .discover))
let matches = try workspace.find(SymbolQuery(pattern: try QueryParser.parse("Client.fetch(id:)")))
let report = try workspace.usages(of: SymbolQuery(pattern: .name("fetch"), containingType: "Client"))
```
