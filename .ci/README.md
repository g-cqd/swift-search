# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`; run the same
checks locally with `.ci/swift-ci local` (quality, the debug tests, the self-analysis).

Each change runs quality (swift-format over the package layout, deadwood, dolly and arcleak over `Sources`, the GCD
ban), the Linux debug, release and AddressSanitizer tests (serial: swift-testing's parallel executor has crashed
the Linux runtime), a smoke run of the built tool on its own sources (it must find `SymbolExtractor`), and the macOS
debug tests. Release and sanitizer runs on macOS are nightly or manual. A `v*` tag builds the Linux and macOS
archives and publishes the release from `release-notes/<tag>.md`.

`baselines/dolly.json` accepts the 17 duplications that predate dolly's adoption; only a new one fails.
