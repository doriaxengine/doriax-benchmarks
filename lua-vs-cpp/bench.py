#!/usr/bin/env python3
"""Times every round of the exported game in Lua, in C++ and with no script.

    bench.py run [--reps 5] [--rounds Arena Crowd Paths Rays] [--label NAME] [--cores 0,2,4,6,8,10]
    bench.py summary [--label NAME]

build.sh makes the game first. It runs on the X display in $DISPLAY (or $BENCH_DISPLAY).

Each run is the release build of the v0.8.5 export, pinned to six performance cores (one thread
each), drawing through Mesa's no-op driver so the GPU never limits a frame: what is timed is the
CPU work of a frame, scripts included. Runs alternate their order, wait for a quiet CPU, and every
frame time is kept in results/<label>/. The script cost of a round is its median frame time minus
the median frame time of the same objects with no script.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"

GAME = ROOT / "build" / "game" / "LuaVsCpp"
ROUNDS = ["Arena", "Crowd", "Paths", "Rays"]
LANGS = ["off", "lua", "cpp"]
CORES = "0,2,4,6,8,10"


def load():
    return os.getloadavg()[0]


def run_one(scene, lang, out, warmup, frames, cores=CORES):
    env = dict(os.environ, DISPLAY=os.environ.get("BENCH_DISPLAY", os.environ.get("DISPLAY", ":0")), GALLIUM_NOOP="1",
               LIBGL_ALWAYS_SOFTWARE="1", vblank_mode="0", BENCH_SCENE=scene, BENCH_LANG=lang,
               BENCH_WARMUP=str(warmup), BENCH_FRAMES=str(frames), BENCH_OUT=str(out))
    env.pop("BENCH_STEP", None)
    log = out.with_suffix(".log")
    t0 = time.time()
    with open(log, "w") as f:
        p = subprocess.run(["taskset", "-c", cores, str(GAME)], cwd=GAME.parent, env=env, stdout=f,
                           stderr=subprocess.STDOUT, timeout=600)
    return p.returncode, time.time() - t0


def run(args):
    folder = RESULTS / args.label
    folder.mkdir(parents=True, exist_ok=True)
    rows = []
    for rep in range(1, args.reps + 1):
        for scene in args.rounds:
            order = LANGS if rep % 2 else LANGS[::-1]
            for lang in order:
                while load() > args.max_load:
                    print(f"  waiting, load {load():.1f}", flush=True)
                    time.sleep(10)
                time.sleep(args.cooldown)
                before = load()
                out = folder / f"{scene}-{lang}-{rep}.json"
                code, took = run_one(scene, lang, out, args.warmup, args.frames, args.cores)
                ok = code == 0 and out.exists()
                frames = json.loads(out.read_text())["frames"] if ok else []
                med = statistics.median(frames) if frames else None
                rows.append(dict(scene=scene, lang=lang, rep=rep, load=before, seconds=round(took, 1),
                                 ok=ok, median_ms=med))
                print(f"{scene:6} {lang:3} rep {rep}  median {med if med is None else round(med, 3)} ms  "
                      f"load {before:.1f}  {took:.0f} s", flush=True)
                (folder / "runs.json").write_text(json.dumps(rows, indent=1))


def summary(args):
    """Median of the runs' medians, in ms per frame, for each kind of timing the runs keep:
    frames/scripts are wall time, framesCpu/scriptsCpu the CPU time of the game's main thread."""
    folder = RESULTS / args.label
    data = {}
    for f in sorted(folder.glob("*-*-*.json")):
        scene, lang, rep = f.stem.split("-")
        run = json.loads(f.read_text())
        for key in ("frames", "scripts", "framesCpu", "scriptsCpu"):
            if run.get(key):
                data.setdefault((key, scene, lang), []).append(statistics.median(run[key]))
    med = lambda *k: statistics.median(data[k]) if k in data else float("nan")
    print(f"{'round':7} {'frame off':>9} {'lua':>8} {'cpp':>8} | {'scripts lua':>11} {'cpp':>7} {'ratio':>6} | "
          f"{'cpu scripts lua':>15} {'cpp':>7} {'ratio':>6}")
    out = {}
    for scene in ROUNDS:
        if ("frames", scene, "lua") not in data:
            continue
        row = {key: {lang: med(key, scene, lang) for lang in LANGS}
               for key in ("frames", "scripts", "framesCpu", "scriptsCpu")}
        r_wall = row["scripts"]["lua"] / row["scripts"]["cpp"]
        r_cpu = row["scriptsCpu"]["lua"] / row["scriptsCpu"]["cpp"]
        out[scene] = dict(row, ratio_wall=r_wall, ratio_cpu=r_cpu,
                          runs={f"{k}/{l}": data.get((k, scene, l)) for k in row for l in LANGS})
        f_, s_, c_ = row["frames"], row["scripts"], row["scriptsCpu"]
        print(f"{scene:7} {f_['off']:9.3f} {f_['lua']:8.3f} {f_['cpp']:8.3f} | {s_['lua']:11.3f} {s_['cpp']:7.3f} "
              f"{r_wall:6.1f} | {c_['lua']:15.3f} {c_['cpp']:7.3f} {r_cpu:6.1f}")
    (folder / "summary.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "summary"])
    ap.add_argument("--label", default="first")
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--rounds", nargs="+", default=ROUNDS)
    ap.add_argument("--warmup", type=int, default=120)
    ap.add_argument("--frames", type=int, default=600)
    ap.add_argument("--cooldown", type=float, default=3.0)
    ap.add_argument("--max-load", type=float, default=4.0)
    ap.add_argument("--cores", default=CORES, help="CPUs to pin the game to, one thread per core")
    a = ap.parse_args()
    run(a) if a.cmd == "run" else summary(a)
