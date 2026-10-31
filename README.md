# swift-search

Finds Swift declarations and their uses, from one binary, three ways:

| Source | Needs | Answers |
| --- | --- | --- |
| the syntax (swift-syntax) | nothing: no build | declarations by name, qualified name, selector, regex; uses by name |
| the compiler's index store | a build of the project | USRs and modules; the uses the compiler resolved to a declaration |
| the toolchain's sourcekit-lsp | a package sourcekit-lsp can open | definition, references, implementations, callers, callees, hover, workspace symbols |

The same queries are a command line (`swift-search find`, `usages`, `lsp`) and a Model Context Protocol server
(`swift-search mcp`).

## Queries

| Query | Finds |
| --- | --- |
| `shared` | every declaration named `shared` |
| `Client.shared`, `Outer.Inner.leaf` | a member whose enclosing types end with these |
| `fetch(id:_:)`, `Client.fetch()` | a callable with exactly these argument labels |
| `/load.*/` | every declaration whose whole name the RE2 expression matches |
| `s:3App6ClientC` | the declaration with this USR (needs `--index-store`) |

Regular expressions run on [AemiRegex](https://github.com/g-cqd/AemiRegex), in time linear in the name: no query, from
the command line or from an MCP client, can make a search exponential.

## Command line

```sh
swift-search find Client.fetch Sources --signature --documentation
swift-search find '/.*Resolver/' --kind struct --kind class --access public --format json
swift-search usages 'Client.fetch(id:)' --index-store          # the uses the compiler resolved
swift-search lsp callers 'welcome(_:)'                          # a query naming one declaration
swift-search lsp references Sources/App/Client.swift:12:17      # or file:line:column (UTF-8 column)
swift-search lsp symbols greet --workspace path/to/package
```

`find` and `usages` take the family's spellings (analyzerkit `AnalyzerCLI`): `--exclude-path`, `--cache-path`,
`--no-cache`, `--index-store`, `--index-store-path`, `--relative-to`. Formats: `text` (default), `xcode` (build-log
notes) and `json` (the family's report envelope: `schemaVersion`, `tool`, `version`, `runNotes`, `skippedFiles`).

Exit status: 0 when something was found, 1 when nothing was (as `grep`), 64 for a usage error (a missing path, no Swift
file, a malformed query), 70 for an internal failure, 74 when the output could not be written.

### What each source can and cannot say

- **Syntax.** Declarations at file and type scope; locals are not indexed. A use is a use of the *name*: a call whose
  argument labels the declaration cannot take, or a use through `Type.` where `Type` is another type of the corpus, is
  left out, and so is a call of a property whose declared type is not a function; everything else is reported and marked
  `(by name)`. An enum case's associated values are its labels: `.moved(by: 1)` is not a use of `case moved(to:)`, but
  a pattern without labels (`case .moved(let value)`) is kept for every case of the name. `Type(...)` is a use of the type, not of its `init`. Facts are cached per file (analyzerkit `CorpusScan`),
  so a second run parses only the files that changed.
- **Index store.** Opened through analyzerkit `IndexStoreSupport`: the store found for the project (SwiftPM's
  `.build`, then Xcode's DerivedData) or `--index-store-path`, its database under the cache directory, never beside the
  store. A file changed since the build is not answered from the index; its uses fall back to the syntax and a run note
  says so.
- **sourcekit-lsp.** The selected toolchain's server (`DEVELOPER_DIR`, else `xcrun --find sourcekit-lsp`), checked by
  analyzerkit's `BinaryTrustChecker` before it runs, in a process group of its own that is stopped with the command.
  Queries answered from sourcekit-lsp's index wait for its background index first (`workspace/synchronize`), which the
  first run in a package builds. An Xcode project needs a build server (for example `xcode-build-server`). A file
  outside every target has no record in sourcekit-lsp's index, nor does a whole package SwiftPM cannot load, as when a
  build-tool plugin does not build (an Xcode-only one importing `XcodeProjectPlugin`; `swiftPM.skipPlugins` does not
  help in 6.4). An empty answer about such a symbol comes with a note that says so (`notes` in JSON and MCP), and
  `usages`, with or without `--index-store-path`, still answers.

## MCP server

```sh
swift-search mcp --root path/to/project        # stdio; --no-lsp leaves out the sourcekit-lsp tools
```

```json
{ "mcpServers": { "swift-search": { "command": "swift-search", "args": ["mcp", "--root", "/path/to/project"] } } }
```

| Tool | Does |
| --- | --- |
| `search_symbols` | `find`, with `context_lines`, `signature`, `body`, `documentation`, `scope` |
| `find_usages` | `usages` |
| `lsp_workspace_symbols` | sourcekit-lsp's `workspace/symbol` |
| `lsp_definition`, `lsp_references`, `lsp_implementations`, `lsp_hover`, `lsp_callers`, `lsp_callees` | the sourcekit-lsp request, at `file`/`line`/`column` or at the one declaration a `symbol` query names |

Paths in answers are relative to the root when inside it. One sourcekit-lsp runs per workspace (at most four), started
on first use and shut down when the input ends. Lines longer than 8 MiB are refused; at most eight requests run at once.

## Libraries

| Product | Holds |
| --- | --- |
| `SwiftSearch` | the query language, the per-file symbol facts, the syntax and index-store resolvers, usages, context |
| `SwiftSearchLSP` | a JSON-RPC client of sourcekit-lsp over the base protocol, on swift-subprocess |
| `SwiftSearchMCP` | the MCP server and its stdio transport |

```swift
let workspace = try await SearchWorkspace.open(.init(paths: ["Sources"], indexStore: .discover))
let matches = try workspace.find(SymbolQuery(pattern: try QueryParser.parse("Client.fetch(id:)")))
let report = try workspace.usages(of: SymbolQuery(pattern: .name("fetch"), containingType: "Client"))
```

## Built on

[analyzerkit](https://github.com/g-cqd/analyzerkit) (source discovery, the facts cache, index-store sessions,
toolchain trust, the CLI option groups and report envelope) and [Aemi](https://github.com/Aemi-Studio/aemi) (bounded
concurrency, the blocking-read pool, the byte kernels under analyzerkit), with AemiJSON for both wires and AemiRegex for
queries. The search was extracted from [SwiftStaticAnalysis](https://github.com/g-cqd/SwiftStaticAnalysis)'s
`SymbolLookup` module.

## Develop

```sh
swift build --build-tests
swift test --skip-build          # builds index stores with swiftc and runs sourcekit-lsp: macOS with Xcode
swift format lint --strict -r Sources Tests Package.swift
```

Swift 6.4, strict concurrency and strict memory safety, warnings as errors. macOS 15 or later; Linux is not tested yet.
