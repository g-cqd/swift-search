---
status: done
blocked-by: []
date: 2026-10-29
---

# 0003 — Decide whether the family's tools share one MCP server

Scope: whether modeler's model (classes, states, check), deadwood's and arcleak's findings are tools of the same MCP
server as the search, through their libraries, or each tool serves its own. Inputs: the analyzerkit revision every
package pins (one per graph), the size of a combined binary, and the JSON-RPC code now written three times (arcleak's
LSP server, swift-search's LSP client and MCP server, ask's MCP client), a candidate for Aemi.

Acceptance: an ADR here or in analyzerkit.

Decided in analyzerkit ADR-0027 (D2, 2026-10-30): one MCP server per tool; a family server is reconsidered when a second
tool serves MCP. The JSON-RPC written three times is now AemiJSON's `AemiJSONRPC` (its roadmap 0006), which this server
adopts in 0007.
