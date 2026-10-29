#!/usr/bin/env python3
"""Copy the original assets and translate the authored Doriax data, without rounding."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import yaml

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True, help="a checkout of github.com/doriaxengine/lostslime3d")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = args.source.resolve()
scenes, bundles = {}, {}
hashes = {}
for pattern, target in [("*.scene", scenes), ("bundles/*.bundle", bundles)]:
    for path in sorted(source.glob(pattern)):
        target[path.stem] = yaml.safe_load(path.read_text())
        hashes[str(path.relative_to(source))] = hashlib.sha256(path.read_bytes()).hexdigest()
for path in sorted((source / "assets").rglob("*")):
    if path.is_file():
        hashes[str(path.relative_to(source))] = hashlib.sha256(path.read_bytes()).hexdigest()
asset_count = sum(path.is_file() for path in (source / "assets").rglob("*"))
for path in sorted((source / "scripts").glob("*")):
    if path.suffix in (".cpp", ".h"):
        hashes[str(path.relative_to(source))] = hashlib.sha256(path.read_bytes()).hexdigest()
shutil.copytree(source / "assets", root / "assets", dirs_exist_ok=True)
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
data = {"scenes": scenes, "bundles": bundles}
(root / "data/source.json").write_text(json.dumps(data, separators=(",", ":")))
(root / "data/provenance.json").write_text(json.dumps({"source": "https://github.com/doriaxengine/lostslime3d", "revision": revision, "sha256": hashes}, indent=2)+"\n")
print(f"Converted {len(scenes)} scenes, {len(bundles)} bundles; copied {asset_count} assets.")
