# Command line

```sh
swift-search find Client.fetch Sources --signature --documentation
swift-search find '/.*Resolver/' --kind struct --kind class --access public --format json
swift-search usages 'Client.fetch(id:)' --index-store         # the uses the compiler resolved
swift-search lsp callers 'welcome(_:)'                        # a query naming one declaration
swift-search lsp references Sources/App/Client.swift:12:17    # or file:line:column (UTF-8 column)
swift-search lsp symbols greet --workspace path/to/package
```

`find` and `usages` take `--exclude-path`, `--cache-path`, `--no-cache`, `--index-store`, `--index-store-path` and `--relative-to`.
`--format` is `text` (default), `xcode` (build-log notes) or `json` (the report format of the other analyzers: `schemaVersion`,
`tool`, `version`, `runNotes`, `skippedFiles`).

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | Something was found. |
| `1` | Nothing was found, as with `grep`. |
| `64` | Usage error: a missing path, no Swift file, a malformed query. |
| `70` | An internal failure. |
| `74` | The output could not be written. |
