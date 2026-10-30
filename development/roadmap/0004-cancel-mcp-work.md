---
status: not-started
blocked-by: [0007]
date: 2026-10-29
---

# 0004 — Stop the work of a cancelled MCP request

Today `notifications/cancelled` suppresses the answer, as the protocol asks, but the search or the sourcekit-lsp request
runs to its end. Scope: each request's task can be cancelled by id, and the language-server request it waits on is
cancelled with `$/cancelRequest`.

Red: a test cancels a request blocked on a scripted server and sees the server receive `$/cancelRequest`.

After 0007 the language-server half comes from `AemiJSONRPC`: a request whose task is cancelled is abandoned and the
server is told with `$/cancelRequest` (`JSONRPCCancellation.languageServer`, tested there). What remains here is mapping
an MCP request id to its task so `notifications/cancelled` cancels it.
