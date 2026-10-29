#!/bin/bash
# Format lint over first-party sources.
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests
