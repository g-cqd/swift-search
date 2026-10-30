---
status: done
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

## Done

Red `904f0b8`, then:

- `LanguageServerConnection` is an adapter over `JSONRPCConnection(framing: .contentLength, cancellation:
  .languageServer)`: the same API and `LanguageServerError`, mapped from `JSONRPCConnectionError` ("the peer's output
  ended" read as "the server's"). New: a request given up at its deadline or by a cancelled caller sends
  `$/cancelRequest` (tested). `MessageSink` is AemiJSONRPC's `JSONRPCSink`. `LSPFrame.swift` (frame and decoder) is
  deleted, and its tests with it; AemiJSONRPC tests that code now.
- `MCPStdio.serve` takes blocks, split by `LineFraming` (an overlong line answered with -32700 and reading resumed, as
  before); `serve(descriptor:)` reads them with `FileDescriptorChunks` on an offload pool, and
  `serveStandardStreams` is that on descriptor 0. The byte-wise `StandardInput` is deleted (H8).

64 tests pass (the four frame tests gone; a deadline test, a blocks test and a megabyte-through-a-pipe test added).
Debug builds before (`358e657`) and after, side by side, load average 250–300:

- An MCP session (initialize, the tool list, `search_symbols`, `find_usages`, `lsp_definition` through the real
  sourcekit-lsp, a malformed line, a blank line, CRLF, pings): the 8 answers byte-equal.
- `swift-search lsp definition` byte-equal. `references` was stopped after 10 minutes on both sides: it waits for
  sourcekit-lsp's background index, which the load starved; not compared.
- 2,000 pings of 550 bytes (1.09 MB) on standard input, three runs each: wall 0.47–0.57 s before, 0.22–0.28 s after;
  user 0.32–0.34 s before, 0.12–0.13 s after.

Not done: release-build numbers; the MCP half of 0004 (cancelling the search a cancelled MCP request runs).
