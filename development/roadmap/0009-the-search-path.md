---
status: not-started
blocked-by: [0008]
date: 2026-10-30
---

# 0009 — The search path: what it builds and never uses

The extraction report's hot spots on `find` and `usages`:

- **H1** references are extracted and cached for every file, and `find` never reads them; extract them only for
  `usages`, or cache them in a payload `find` does not decode.
- **H2** `usesByName` is built over the whole corpus on every run, for a query about one name; build it for the names
  the query can match, or keep it in the cache.
- **H4** an index query by regular expression asks IndexStoreDB for every symbol name and filters them; use a literal
  prefix the expression requires (AemiRegex roadmap 0016, `requiredLiterals`) to narrow the names first.
- **H6** discovery runs again for each path argument and for the index; once per run, shared.

(H3, the per-match freshness lookups, goes with 0006.)

Red per item: a counter test (files whose references are decoded by `find`; names visited by an index regex query with
a literal; discovery calls per run) that fails today. Acceptance: 0008's warm `find` budget.
