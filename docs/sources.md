# What each source can and cannot say

## Syntax

Needs nothing but the source. Declarations at file and type scope are found; locals are not indexed.

A use is a use of the **name**. A call is left out when the declaration cannot take its argument labels, when it goes through
`Type.` and `Type` is another type in the analyzed files, or when it calls a property whose declared type is not a function.
Everything else is reported and marked `(by name)`.

- An enum case's associated values are its labels: `.moved(by: 1)` is not a use of `case moved(to:)`.
- A pattern without labels (`case .moved(let value)`) is left out when its subject's written type is another type in the analyzed
  files, including through `switch self` in another enum, a parameter declared as one, and a `catch` under `do throws(Other)`. It is
  followed through the cases it is nested in. Otherwise, as for a `catch` whose thrown type is inferred, it is kept for every case
  of that name.
- `Type(...)` is a use of the type, not of its `init`.

Facts are cached per file, so a second run parses only the files that changed.

## Index store

Needs a build. The store is found for the project (SwiftPM's `.build`, then Xcode's DerivedData) or given with
`--index-store-path`. Its database lives under the cache directory, never beside the store. A file changed since the build is not
answered from the index: its uses fall back to the syntax, and a run note says so.

## sourcekit-lsp

Uses the selected toolchain's server (`DEVELOPER_DIR`, else `xcrun --find sourcekit-lsp`), checked for trust before it runs, in a
process group of its own that stops with the command. Queries answered from its index wait for its background index first, which
the first run in a package builds.

- An Xcode project needs a build server, for example `xcode-build-server`.
- A file outside every target has no record in the index, and neither does a package SwiftPM cannot load, such as one whose
  build-tool plugin does not build (an Xcode-only one importing `XcodeProjectPlugin`).
- An empty answer about such a symbol comes with a note that says so (`notes` in JSON and MCP). `usages` still answers.
