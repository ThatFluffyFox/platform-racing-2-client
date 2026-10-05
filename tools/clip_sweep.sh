#!/usr/bin/env bash
# Sweep stat/input combinations against an inside corner and report every run
# where the player clips into solid blocks. Pass --help for the options.
#
# The sweep runs the real LocalPlayerController, compiled to JS and run with
# Node (much faster than `haxe --interp` for tens of thousands of runs).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test/output
"${HAXE:-haxe}" tools/clip_sweep.hxml
exec node --require ./tools/clip_sweep_shim.cjs test/output/clip_sweep.js "$@"
