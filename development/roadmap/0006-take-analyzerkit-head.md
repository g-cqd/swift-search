---
status: not-started
blocked-by: [analyzerkit 0050, 0051, 0052, 0053, 0056]
date: 2026-10-30
---

# 0006 — Take analyzerkit's head

swift-search pins analyzerkit `651d1ac`; the tools pin `08f09a3`. After analyzerkit's step 1 (research
2026-10-29-schedule, revision 2026-10-30) it moves to that head, deleting what analyzerkit now holds:

| Here | There |
| --- | --- |
| `SourcePath+Absolute.swift` | `SourcePath.absolute` (analyzerkit 0050) |
| `TextPositions` (whole lines decoded per call, H10) | the line index (0051) |
| the `sourcekit-lsp` lookup in `SourceKitLSP` | `ToolchainResolution` (0052) |
| an `isCurrent` call per match (H3) | the session's freshness memo (0053) |
| the literal 1 for no match | `ExitStatus.noMatch` (0056, ADR-0026) |

indexstore-db stays at `0390867`, written exactly as analyzerkit writes it (ADR-0025); aemi, AemiJSON and AemiRegex at
the revisions analyzerkit's head resolves.

Red: the suite as it is (63 tests) against the new head before the deletions; then the deletions with every output
byte-equal on the fixtures, and `find`'s calls to the freshness lookup counted (one per file, not per match).
