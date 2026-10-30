---
status: not-started
blocked-by: [0008]
date: 2026-10-30
---

# 0012 — Start-up, cache size, build

The report's remaining hot spots, measured before anything is changed:

- **H9** every `swift-search lsp` command starts sourcekit-lsp and waits for its index (0.4–1.8 s on the probe package).
  The MCP server already keeps one per workspace (`LanguageServerPool`); for the command line, record the cost and decide
  whether a reuse is worth a daemon (probably not: ADR-0001 keeps the server out of process and short-lived).
- **H11** the facts cache's size on the reference app against the other tools' (analyzerkit research 2026-10-29-performance:
  4.3 MB to 27 MB); if references dominate, 0009's split shrinks it.
- **H12** the release build (263 s from a debug-built tree) and the 28.3 MB binary: which modules weigh most
  (`-Xlinker -map`), against analyzerkit 0034.

Acceptance: a table in the diary and a decision per item; code only where a budget fails.
