#!/usr/bin/env bash
# Real-renderer test: needs a working graphical display. It does not test sound output.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP/data"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"${GODOT_BIN:-godot}" --path "$ROOT" --resolution 480x800 --audio-driver Dummy --script tests/capture_native.gd
