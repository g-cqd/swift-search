---
status: not-started
blocked-by: [analyzerkit ADR-0025]
date: 2026-10-29
---

# 0001 — Link sourcekit-lsp into the binary

Scope: an `InProcessLanguageServer` beside the process client (ADR-0001), behind a package trait so the default build
does not pay for SwiftPM and swift-docc, with the same `LanguageServerSession` surface.

Blocked by analyzerkit ADR-0025 (2026-10-30): SwiftPM refuses two requirements on indexstore-db written differently, even
a revision and a branch naming the same commit, and sourcekit-lsp's tags require `branch: "release/6.4.x"`. The family
keeps one revision of upstream `main`, because its concurrent record reads halve the reference scans deadwood and arcleak
make (1.14 s against 2.24 s on the reference app's store); the release branch lacks them. This entry can move only if a
sourcekit-lsp tag requires the family's revision, or the family's measurement changes; until then sourcekit-lsp runs
out of process (ADR-0001).

Red: the resolution probe of ADR-0001 resolves; a test runs `definition` through both clients on the demo package of
`SourceKitLSPTests` and compares the answers.

Acceptance: the trait-enabled binary answers every `lsp` operation with no `sourcekit-lsp` executable on the machine
(sourcekitd still comes from the toolchain); its size and release build time are in the diary.
