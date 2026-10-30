---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0002 — Propose the per-file symbol facts for analyzerkit

Scope: an analyzerkit record (ADR, then roadmap entry there) proposing `SymbolExtractor`, `FileSymbols`, `Declaration`
and `Reference` as a product, consumed by swift-search and deadwood (whose `DeclarationCollector` and
`ReferenceCollector` are the same lineage), and by modeler for its type facts if it wants them.

Red: deadwood's and swift-search's extraction compared on a pinned g-cqd package: which declarations and references
each records and why they differ, measured, before any code moves.

Acceptance: the ADR in analyzerkit names the consumers and the differences; nothing moves without it (analyzerkit
WHITE-PAPER, "Where code lives").

analyzerkit ADR-0027 (2026-10-30) accepts P1 and P2 once measured; the comparison is analyzerkit roadmap 0055, which
this entry becomes on that side. Here it closes when 0055 does.
