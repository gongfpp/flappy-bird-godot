#!/bin/sh
# Run from any working directory; keep test user data separate from real saves.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/sky-hop-tests.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/data" "$test_root/cache"
XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" \
    "${GODOT_BIN:-godot}" --headless --path "$project_root" --script tests/run_tests.gd
