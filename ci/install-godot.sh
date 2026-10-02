#!/usr/bin/env bash
# Official Godot 4.6.3 release assets. SHA-256 values are the official GitHub
# release asset digests; reject mismatches rather than executing new bytes.
set -euo pipefail
version="${GODOT_VERSION:-4.6.3}"
[[ "$version" == 4.6.3 ]] || { echo 'Update the pinned checksums before changing Godot.' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
base="https://github.com/godotengine/godot-builds/releases/download/${version}-stable"
engine="Godot_v${version}-stable_linux.x86_64.zip"
templates="Godot_v${version}-stable_export_templates.tpz"
curl --fail --location --retry 3 --output "$work/$engine" "$base/$engine"
curl --fail --location --retry 3 --output "$work/$templates" "$base/$templates"
(
  cd "$work"
  printf '%s  %s\n' \
    d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3 "$engine" \
    3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8 "$templates" | sha256sum --check
)
mkdir -p "$HOME/.local/bin"
unzip -q "$work/$engine" -d "$work/engine"
install -m 755 "$work/engine/Godot_v${version}-stable_linux.x86_64" "$HOME/.local/bin/godot"
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
mkdir -p "$template_dir"
unzip -q -j "$work/$templates" 'templates/web_nothreads_release.zip' -d "$template_dir"
test -s "$template_dir/web_nothreads_release.zip"
echo "$HOME/.local/bin" >> "$GITHUB_PATH"
"$HOME/.local/bin/godot" --version
sha256sum "$template_dir/web_nothreads_release.zip"
