# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`; run the same
checks locally with `.ci/swift-ci local` (quality, the debug tests, the self-analysis).

Each change runs quality (swift-format over the package layout, deadwood, dolly and arcleak over `Sources`, the GCD
ban), the Linux debug, release and AddressSanitizer tests (serial: swift-testing's parallel executor has crashed
the Linux runtime), a smoke run of the built tool on its own sources (it must find `SymbolExtractor`), and the macOS
debug tests. Release and sanitizer runs on macOS are nightly or manual. A `v*` tag builds the Linux and macOS
archives and publishes the release from `release-notes/<tag>.md`.

`baselines/dolly.json` accepts the 17 duplications that predate dolly's adoption; only a new one fails.

## Linux AddressSanitizer: two reported leaks that are not leaks

`swift.linuxLeakSuppressions` lists two stack symbols (substrings of the mangled names; a leading `$` would be suppression-file
syntax). Both are heap objects that something still holds when the process ends, which LeakSanitizer does not see:

- `s12AemiJSONCore9JSONValueO17dictionaryLiteral`: the tool schemas in `ToolCatalog` are `static let` JSON values, built once
  by `JSONValue.dictionaryLiteral` and kept for the life of the process.
- `25generator`: the argument arrays that Swift Testing builds for a parameterized `@Test`. Hoisting the arrays into `static let`s
  moves the report to the static's initializer, so the test source cannot avoid it.

Reproduce: `swift:6.4.1-noble`, `swift test --sanitize=address --scratch-path /tmp/b` with `LSAN_OPTIONS=suppressions=<file with
the three lines swift-ci writes by default>`; without the two entries it reports 112 bytes in 2 allocations (the generators) and
2648 bytes in 26 allocations (the schemas), and with them it exits 0. Remove the entries when a Swift toolchain run without them
is clean.
