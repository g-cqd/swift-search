---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0005 — Build and test on Linux

The index store is macOS-only by design (IndexStoreDB is linked on macOS only). The syntax search, the MCP server and the
sourcekit-lsp client have no macOS-only code that is known, but none of it has been built on Linux.

Acceptance: the family's shared CI workflow green on Linux; the index-store and sourcekit-lsp tests disabled there with
`.enabled(if:)` and a reason.
