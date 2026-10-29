#!/usr/bin/env python3
"""Verify that the port's authored content and assets match its recorded source."""
import argparse
import hashlib
import json
from pathlib import Path
import yaml

root = Path(__file__).resolve().parents[1]
provenance = json.loads((root / "data/provenance.json").read_text())
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True, help="a checkout of " + provenance["source"] + " at " + provenance["revision"][:7])
args = parser.parse_args()
snapshot = json.loads((root / "data/source.json").read_text())
count = 0
for relative, expected in provenance["sha256"].items():
    original = args.source / relative
    assert hashlib.sha256(original.read_bytes()).hexdigest() == expected, "Source changed: " + relative
    if relative.startswith("assets/"):
        assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == expected, "Port asset changed: " + relative
        count += 1
    elif relative.endswith(".scene"):
        assert snapshot["scenes"][original.stem] == yaml.safe_load(original.read_text()), relative
    elif relative.endswith(".bundle"):
        assert snapshot["bundles"][original.stem] == yaml.safe_load(original.read_text()), relative
print(f"PASS: {len(snapshot['scenes'])} scenes, {len(snapshot['bundles'])} bundles, {count} byte-identical assets, and original script hashes.")
