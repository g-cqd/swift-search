---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0008 — Benchmarks against the budgets

analyzerkit roadmap 0029 sets swift-search's budgets on a 5,000-file corpus: warm `find` < 0.2 s and < 100 MB peak
resident, cold `find` < 1 s, repeated MCP `search_symbols` < 50 ms per call. Only SwiftStaticAnalysis's 156 files have
been measured (0.06 s cold, 0.03 s warm).

Scope: a `Scripts/timings.sh` like analyzerkit's `probes/perf/timings.sh` (cold, cache-writing, warm; `/usr/bin/time -l`
for peak resident), and an MCP driver that sends 100 `search_symbols` calls over one server and reports the median and
the slowest after the first. Corpus: the reference app's working tree (2,973 files) and a pinned g-cqd snapshot.

Red: the thresholds, set from the budgets, fail where they fail today; the table goes in the diary, and the hot-spot
entries (0009–0012) are ordered by what the profile of each failing budget shows.
