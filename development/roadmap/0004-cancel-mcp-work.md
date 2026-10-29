---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0004 — Stop the work of a cancelled MCP request

Today `notifications/cancelled` suppresses the answer, as the protocol asks, but the search or the sourcekit-lsp request
runs to its end. Scope: each request's task can be cancelled by id, and the language-server request it waits on is
cancelled with `$/cancelRequest`.

Red: a test cancels a request blocked on a scripted server and sees the server receive `$/cancelRequest`.
