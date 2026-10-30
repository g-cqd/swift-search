---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0007 — Speak JSON-RPC through AemiJSONRPC

AemiJSON's `AemiJSONRPC` (its roadmap 0006, `e90d11c`) was ported from this package's `LSPFrame`, `LSPFrameDecoder`,
`LanguageServerConnection` and `MCPStdio`, with ask's lessons. Replace all four:

- the language-server client on `JSONRPCConnection(framing: .contentLength, cancellation: .languageServer)`, the
  server's requests answered by `onRequest`, its notifications to `onNotification`;
- the MCP server reading standard input through `FileDescriptorChunks` and `LineFraming`: one `read` per 64 KiB block,
  where `MCPStdio` makes one call per byte (H8); an overlong line answered with a parse error and reading resumed;
- `JSONRPCMessage.Invalid.response()` for what cannot be read.

Red: the existing LSP and MCP tests unchanged; a new one feeding 1 MiB of requests through a pipe counts the reads (16,
not 1,048,576). Bar: the MCP server's per-call overhead measured before and after in the diary.

Not here: AemiJSONRPC's single watchdog timer (its 0006 "not done"); each request still sleeps in its own child task.
