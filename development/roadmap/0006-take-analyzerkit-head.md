---
status: done
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

## Done

Step 1 (`358e657`): the pins moved to analyzerkit `6c8f556`, aemi `5e56014`, AemiJSON `44aed49`, AemiRegex `637ffee`
(indexstore-db unchanged, as analyzerkit writes it); the 63 tests passed unchanged. Red `bdbe689`: an LSP offset inside
a surrogate pair names its scalar's start; a relative `--sourcekit-lsp` is refused for being relative. Then:

- `TextPositions` is a wrapper over `LineIndex`, built from the bytes already read (no second decode); its tests stand.
- `SourceKitLSP.locate` takes the server beside the library `ToolchainResolution` selects, and checks an explicit one
  with `explicitSourceKitLSP`; a test checks it finds what analyzerkit resolves.
- `IndexStoreResolver.isCurrent` is the session's `freshness` (H3): no per-call memo; the analyzed files cost nothing,
  others one lookup per session.
- `SourcePath+Absolute.swift` is deleted for analyzerkit's `SourcePath.absolute`.
- The commands return `ExitStatus` through analyzerkit's `SearchOutcome`: 0, 1, and now 70 when no file found could
  be read (the local `SearchOutcome` enum is gone).

67 tests pass. The release before and after, built side by side (`/tmp/ss-step1` at `358e657`), give byte-equal standard
output, standard error and exit status on ten runs: `find` in text, JSON and Xcode formats with context, no match (1),
a missing path (64), `--relative-to`, `usages` in text and JSON, and `find`/`usages` with `--index-store` on this
package's own build.

Not done: a test counting the freshness lookups through swift-search (analyzerkit's `IndexFreshnessTests` count them
there); `NameExpression` still anchors by hand instead of AemiRegex's `wholeMatch` (correct since its 0015; a separate
change with its own probe).
