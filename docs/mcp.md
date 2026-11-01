# MCP server

```sh
swift-search mcp --root path/to/project    # stdio; --no-lsp leaves out the sourcekit-lsp tools
```

```json
{
  "mcpServers": {
    "swift-search": {
      "command": "swift-search",
      "args": ["mcp", "--root", "/path/to/project"]
    }
  }
}
```

| Tool | Does |
| --- | --- |
| `search_symbols` | `find`, with `context_lines`, `signature`, `body`, `documentation` and `scope`. |
| `find_usages` | `usages`. |
| `lsp_workspace_symbols` | sourcekit-lsp's `workspace/symbol`. |
| `lsp_definition`, `lsp_references`, `lsp_implementations`, `lsp_hover`, `lsp_callers`, `lsp_callees` | The sourcekit-lsp request, at `file`, `line` and `column`, or at the one declaration a `symbol` query names. |

Paths in answers are relative to the root when inside it. One sourcekit-lsp runs per workspace (at most four), started on first use
and stopped when the input ends. Lines over 8 MiB are refused, and at most eight requests run at once.
