#!/usr/bin/env python3
"""Stamp the actual source commit and produce a byte-verifiable Web manifest."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
commit = os.environ["GITHUB_SHA"]
assert re.fullmatch(r"[0-9a-f]{40}", commit), "Expected full source SHA"
for name in ("index.html", "index.js", "index.wasm", "index.pck"):
    assert (root / name).is_file() and (root / name).stat().st_size, name
html = root / "index.html"
text = html.read_text()
text = text.replace("</head>", f'<meta name="source-commit" content="{commit}">\n</head>')
text = text.replace("</body>", f'<a href="version.json" title="Build {commit}" style="position:fixed;bottom:5px;left:8px;z-index:10;color:#a8b2c8;font:10px monospace;text-decoration:none">build {commit[:7]}</a>\n</body>')
html.write_text(text)
(root / ".nojekyll").touch()
files = {
    p.name: {"sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bytes": p.stat().st_size}
    for p in sorted(root.iterdir()) if p.is_file() and p.name not in ("version.json", "SHA256SUMS")
}
version = {
    "name": "Sky Hop", "commit": commit, "godot": os.environ.get("GODOT_VERSION", "4.6.3"),
    "renderer": "Compatibility / WebGL 2", "threads": False,
    "repository": os.environ.get("GITHUB_REPOSITORY", "gongfpp/flappy-bird-godot"),
    "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "files": files,
}
(root / "version.json").write_text(json.dumps(version, indent=2) + "\n")
(root / "SHA256SUMS").write_text("".join(
    f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
    for p in sorted(root.iterdir()) if p.is_file() and p.name != "SHA256SUMS"
))
print(json.dumps(version, indent=2))
