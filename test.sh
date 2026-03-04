#!/usr/bin/env bash
set -e

ODIN_BIN="$HOME/Downloads/odin-linux-amd64-nightly+2026-02-04/odin"
mkdir -p bin

"$ODIN_BIN" test engine/app
"$ODIN_BIN" test engine/assets
"$ODIN_BIN" build examples/headless_smoke -collection:thor=. -out:bin/headless_smoke_test -debug
./bin/headless_smoke_test
