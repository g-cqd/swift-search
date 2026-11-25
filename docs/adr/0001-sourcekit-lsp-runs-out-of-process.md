---
status: accepted
date: 2026-10-29
---

# 0001 — sourcekit-lsp runs as the toolchain's process, not linked into the binary

## Context

The goal was one binary with every feature: the syntax search, the index store and sourcekit-lsp. sourcekit-lsp ships a
library product, `InProcessClient` (`InProcessSourceKitLSPClient`), that runs the server in the caller's process, so
linking it looked possible.

Probe (diary 2026-10-29-01): a package depending on analyzerkit (651d1ac) and sourcekit-lsp `swift-6.4.1-RELEASE`
(1c9871b) does not resolve:

> error: indexstore-db is required using two different revision-based requirements
> (0390867818c28241af4650eb4ef29af5669335a3 and release/6.4.x), which is not supported

analyzerkit pins indexstore-db to a revision (ADR-0004 of analyzerkit: arcleak and deadwood must pin the same one);
every sourcekit-lsp tag requires it by branch. SwiftPM has no override for two unversioned requirements. The same probe
without analyzerkit resolves: a branch requirement wins over a version range (swift-syntax `604.0.0` against
`release/6.4.x`, which is the same commit), so indexstore-db is the only blocker. Linking would also bring SwiftPM,
llbuild, swift-driver, swift-docc, swift-nio and swift-crypto into the build, and the server would still load
`sourcekitd` from the installed toolchain at run time.

## Decision

1. `SwiftSearchLSP` speaks JSON-RPC to the selected toolchain's `sourcekit-lsp` executable over a pipe, on
   swift-subprocess. The executable is found as analyzerkit finds `libIndexStore` (`DEVELOPER_DIR`, then `xcrun`) and
   passes analyzerkit's `BinaryTrustChecker` before it runs.
2. The binary stays the one place for every feature: `swift-search lsp` and the `lsp_` MCP tools start, use and stop
   the server themselves.
3. Linking `InProcessClient` is roadmap 0001, blocked on the indexstore-db requirement of analyzerkit.

## Consequences

- The server always matches the toolchain that built the project and its index; a linked server would be pinned to the
  sourcekit-lsp version swift-search was built with.
- A machine without a toolchain has no `lsp` features; it has no index store either.
- Each `swift-search lsp` command pays a server start (about 0.4 s on the probe package); the MCP server keeps one
  session per workspace.
