---
status: accepted
date: 2026-10-29
---

# 0002 — swift-search is a tool of its own, not a command of modeler

## Context

The owner asked whether the search should merge with modeler. Read on 2026-10-29 (diary 2026-10-29-01):

| Tool | Facts it extracts | Overlap with the search |
| --- | --- | --- |
| modeler | types, their stored properties, enum cases, methods with labels, the effects of each body on its own type's members | type and member names only: no top-level declarations, access levels, columns, or uses across types |
| deadwood | every declaration and reference, with scopes (lifted from SwiftStaticAnalysis like the search) | the closest, but internal types tuned to reachability |
| arcleak | an LSP *server* for its diagnostics | none in the facts; a second JSON-RPC framing |
| dolly, fcheck | tokens and clones; obligations on paths | none |

## Decision

1. The search is its own package and binary: its dependencies (IndexStoreDB opened for queries, swift-subprocess for
   sourcekit-lsp, an MCP server) are none of modeler's, and modeler is due to migrate onto the shared foundations
   (analyzerkit roadmap 0022) without new surface.
2. It uses the family's foundations as modeler does: analyzerkit `SourceCorpus` and `CorpusScan` for discovery and the
   per-file facts cache, `IndexStoreSupport`, `ProjectModel`, `AnalyzerCLI`, `ReportSupport`; Aemi for concurrency.
3. What it shares with the others is proposed for analyzerkit, not copied (roadmap 0002): the per-file declarations and
   references.

## Consequences

- A merge stays possible: `SwiftSearch` is a library, and a modeler command or MCP tool can call it once both packages
  pin the same analyzerkit revision (every family package pins analyzerkit by revision).
- An agent that wants both the search and modeler's diagrams runs two MCP servers until roadmap 0003.
