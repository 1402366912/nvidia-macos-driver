#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Apply source patch only; no downloads/builds/installation/device access."""
import hashlib
import json
import pathlib
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("Usage: apply_to_asussmc.py /path/to/clean/pinned/AsusSMC")
base = pathlib.Path(__file__).resolve().parents[1]
repo = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((base / "upstream-manifest.json").read_text())
head = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                      check=True, text=True, capture_output=True).stdout.strip()
if head != manifest["upstream_commit"]:
    sys.exit("Refusing: checkout HEAD is not the pinned AsusSMC commit.")
for name, expected in manifest["sha256_before"].items():
    path = repo / name
    if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        sys.exit("Refusing: changed/missing/symlink input " + name)
for name in manifest["added_paths"]:
    path = repo / name
    if path.exists() or path.is_symlink():
        sys.exit("Refusing: added path already exists " + name)
patch = str(base / "patches/AsusSMC-FX505GT.patch")
subprocess.run(["git", "-C", str(repo), "apply", "--check", patch], check=True)
subprocess.run(["git", "-C", str(repo), "apply", patch], check=True)
for name, expected in manifest["sha256_after"].items():
    if hashlib.sha256((repo / name).read_bytes()).hexdigest() != expected:
        sys.exit("Post-apply verification failed: " + name)
print("Applied and hash-verified source-only patch. No build, install or hardware access occurred.")
