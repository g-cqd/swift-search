---
status: not-started
blocked-by: [0008]
date: 2026-10-30
---

# 0010 — Context parsed once per file, files in parallel

**H5**: `SymbolContextExtractor` parses a file's syntax again for each match in it, and matches are processed one after
another. Parse each file holding matches once, extract the context of all its matches from that tree, and run the files
through analyzerkit's bounded `mapConcurrently`, keeping the output order.

Red: a parse counter on a fixture with 20 matches in 3 files (3 parses, not 20); output byte-equal to today's on the
fixtures. Acceptance: `find --context` on the reference app within 0008's cold budget.
