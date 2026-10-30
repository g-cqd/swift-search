---
status: not-started
blocked-by: [0007, 0008]
date: 2026-10-30
---

# 0011 — The MCP server keeps its workspace

**H7**: each `search_symbols` call opens a `SearchWorkspace` (discovery, cache load, index session) and drops it. Keep
one per root for the server's life, refreshed when a file's modification time or the set of files changes (analyzerkit's
discovery and facts cache already key on both), and the index session reopened only when the store changes.

Red: 100 calls over one server open the workspace once; a file edited between two calls is seen by the second; a file
added is found. Acceptance: 0008's MCP budget (< 50 ms per call after the first).
