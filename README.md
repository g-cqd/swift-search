# swift-search

Finds Swift declarations and their uses, from one binary, in three ways, from the command line or over the
[Model Context Protocol](https://modelcontextprotocol.io) for an agent.

| Source | Needs | Answers |
| --- | --- | --- |
| The syntax | Nothing: no build. | Declarations by name, qualified name, selector or regex; uses by name. |
| The compiler's index store | A build of the project. | USRs and modules; the uses the compiler resolved to a declaration. |
| The toolchain's sourcekit-lsp | A package it can open. | Definition, references, implementations, callers, callees, hover, workspace symbols. |

```sh
swift-search find Client.fetch Sources --signature
swift-search find '/.*Resolver/' --kind struct --access public
swift-search usages 'Client.fetch(id:)' --index-store
swift-search lsp callers 'welcome(_:)'
swift-search mcp --root path/to/project
```

## Install

Build with Swift 6.4 on macOS 15 or later (Linux is not tested yet):

```sh
swift build -c release
cp .build/release/swift-search /usr/local/bin/
```

## Learn more

[User guide](docs/README.md): queries, the command line, what each source can say, the MCP server, the library.

swift-search shares its source discovery, cache and reports with the [analyzers](https://github.com/g-cqd/analyzerkit)
([arcleak](https://github.com/g-cqd/arcleak), [deadwood](https://github.com/g-cqd/deadwood), [dolly](https://github.com/g-cqd/dolly)),
and began as the symbol search of [SwiftStaticAnalysis](https://github.com/g-cqd/SwiftStaticAnalysis).

[MIT](LICENSE)
