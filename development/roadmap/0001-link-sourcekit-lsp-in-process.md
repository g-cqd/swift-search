---
status: not-started
blocked-by: [analyzerkit indexstore-db requirement]
date: 2026-10-29
---

# 0001 — Link sourcekit-lsp into the binary

Scope: an `InProcessLanguageServer` beside the process client (ADR-0001), behind a package trait so the default build
does not pay for SwiftPM and swift-docc, with the same `LanguageServerSession` surface.

Blocked by: analyzerkit requires indexstore-db by revision; sourcekit-lsp requires it by branch (`release/6.4.x` for
`swift-6.4.1-RELEASE`). Unblocking is a family decision (analyzerkit ADR-0004 asks arcleak and deadwood to pin the same
revision): analyzerkit, arcleak and deadwood move to `branch: "release/6.4.x"`, or to whatever requirement the
sourcekit-lsp tag in use names.

Red: the resolution probe of ADR-0001 resolves; a test runs `definition` through both clients on the demo package of
`SourceKitLSPTests` and compares the answers.

Acceptance: the trait-enabled binary answers every `lsp` operation with no `sourcekit-lsp` executable on the machine
(sourcekitd still comes from the toolchain); its size and release build time are in the diary.
