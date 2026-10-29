#!/usr/bin/env python3
"""Medians of a results folder, per test and engine.

    summary.py results/<label> [results/<label> ...]
"""
import json
import statistics
import sys
from pathlib import Path


def median(rows, key):
    values = [r[key] for r in rows if key in r]
    return statistics.median(values) if values else float("nan")


def low1(folder, row):
    """1% low from the raw frame times, for runs saved before run.py recorded it."""
    stem = f"{row['engine']}-{(row.get('scene') or row.get('case')).replace(' ', '-').lower()}-{row['run']}"
    frames = json.loads((folder / "raw" / f"{stem}.json").read_text())["frame_ms"]
    return 1000 / statistics.fmean(sorted(frames, reverse=True)[:max(1, len(frames) // 100)])


def show(folder):
    rows = [r for r in json.loads((folder / "runs.json").read_text()) if "fps" in r]
    failed = sum(1 for r in json.loads((folder / "runs.json").read_text()) if "error" in r)
    for r in rows:
        if "low1_fps" not in r:
            r["low1_fps"] = low1(folder, r)
    tests = list(dict.fromkeys(r.get("scene") or r.get("case") for r in rows))
    print(f"{folder}  ({len(rows)} runs{f', {failed} failed' if failed else ''})")
    print(f"  {'test':24s} {'Doriax FPS':>11s} {'Godot FPS':>10s} {'ratio':>6s}   {'1% low D / G':>15s}"
          f"   {'CPU ms D / G':>13s}   {'RSS MiB D / G':>13s}")
    for test in tests:
        d = [r for r in rows if r["engine"] == "doriax" and (r.get("scene") or r.get("case")) == test]
        g = [r for r in rows if r["engine"] == "godot" and (r.get("scene") or r.get("case")) == test]
        if not d or not g:
            continue
        fd, fg = median(d, "fps"), median(g, "fps")
        print(f"  {test:24s} {fd:11.1f} {fg:10.1f} {fd / fg:6.2f}   {median(d, 'low1_fps'):7.0f} / {median(g, 'low1_fps'):<6.0f}"
              f"   {median(d, 'cpu_ms'):5.3f} / {median(g, 'cpu_ms'):<5.3f}   {median(d, 'rss_mib'):5.0f} / {median(g, 'rss_mib'):<5.0f}")
    print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for arg in sys.argv[1:]:
        show(Path(arg))
