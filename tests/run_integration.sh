#!/bin/sh
# The real scene creates a default SaveStore during instantiation, so isolate
# even that constructor's initial load from the user's game data.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/sky-hop-integration.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/data" "$test_root/cache"
status=0
SKY_HOP_ISOLATED_TESTS=1 XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" \
    "${GODOT_BIN:-godot}" --headless --path "$project_root" --script tests/run_integration.gd \
    > "$test_root/output.log" 2>&1 || status=$?
cat "$test_root/output.log"
# Godot can report shutdown leaks despite exiting zero. Treat integration
# script/engine errors and ObjectDB leak diagnostics as failures as well.
if grep -Eq '^(SCRIPT ERROR:|ERROR:|WARNING: ObjectDB instances leaked)' "$test_root/output.log"; then
    printf '%s\n' 'Integration failed: engine/script error or shutdown leak diagnostic.' >&2
    status=1
fi
exit "$status"
