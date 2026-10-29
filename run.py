#!/usr/bin/env python3
"""Runs Doriax and Godot one after the other, alternating which goes first, and writes every run to
results/<label>/. Each run waits until the CPU package is below --max-temp, sleeps --cooldown seconds,
then starts pinned to --cores.

    run.py scenes --label L [--scene crowd island]
    run.py game   --label L [--level "Level One" "Level Two"]
    run.py suite  --label L [--case sprites_static_3000 ...]

Per run it records FPS over the measured window, mean and p99 frame time, the 1% low (FPS of the
slowest 1% of frames), CPU time per frame (all threads, from /proc), resident memory at the end and
its peak, and draw calls.
"""
import argparse
import datetime
import json
import math
import os
import selectors
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
GODOT_ARGS = ["--display-driver", "x11", "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy"]
TICKS = os.sysconf("SC_CLK_TCK")

MODES = {
    "scenes": dict(items=["crowd", "island"], warmup=3, duration=20,
                   doriax=BUILD / "scenes/doriax/doriax-scenes", godot=BUILD / "scenes/godot-export/scenes.x86_64"),
    "game": dict(items=["Level One", "Level Two"], warmup=5, duration=20,
                 doriax=BUILD / "game/doriax/LostSlime3D", godot=BUILD / "game/godot-export/LostSlime3D.x86_64"),
    "suite": dict(items=["sprites_static_3000", "sprites_moving_3000", "sprites_static_10000", "sprites_moving_10000",
                         "sprites_multitex_3000", "cubes_static_1000", "cubes_static_3000", "cubes_moving_1000",
                         "cubes_lit_1000", "cubes_instanced_3000", "models_1000", "models_moving_1000"],
                  warmup=2, duration=8,
                  doriax=BUILD / "suite/doriax/doriax-suite", godot=BUILD / "suite/godot-export/suite.x86_64"),
}


def cpu_seconds(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / TICKS


def status_mib(pid, key):
    line = next(l for l in Path(f"/proc/{pid}/status").read_text().splitlines() if l.startswith(key))
    return int(line.split()[1]) / 1024


def pkg_temp():
    """CPU package temperature in C, 0 when there is no sensor to read."""
    for zone in Path("/sys/class/thermal").glob("thermal_zone*"):
        if (zone / "type").read_text().strip() == "x86_pkg_temp":
            return int((zone / "temp").read_text()) / 1000
    for mon in Path("/sys/class/hwmon").glob("hwmon*"):  # AMD
        if (mon / "name").read_text().strip() in ("k10temp", "zenpower") and (mon / "temp1_input").exists():
            return int((mon / "temp1_input").read_text()) / 1000
    return 0.0


def stats(frames):
    total = sum(frames)
    slowest = sorted(frames, reverse=True)[:max(1, len(frames) // 100)]
    return dict(frames=len(frames), fps=1000 * len(frames) / total, frame_ms=total / len(frames),
                p99_ms=sorted(frames)[int(len(frames) * 0.99)], low1_fps=1000 / statistics.fmean(slowest))


def command(mode, engine, binary, item, output, args):
    """The command line and environment of one run."""
    if mode == "game":
        if engine == "godot":
            return [str(binary)] + GODOT_ARGS[:4] + ["--", "--bench", "--level", item, "--duration", str(args.duration),
                                                     "--warmup", str(args.warmup), "--output", str(output),
                                                     "--light-scale", "0.32"], {}
        return [str(binary)], {"LOSTSLIME_BENCH_LEVEL": item, "LOSTSLIME_BENCH_OUTPUT": str(output),
                               "LOSTSLIME_BENCH_ROUTES": str(ROOT / "game/godot/benchmark/routes.json"),
                               "LOSTSLIME_BENCH_DURATION": str(args.duration), "LOSTSLIME_BENCH_WARMUP": str(args.warmup)}
    env = {"BENCH_SHARED": str(BUILD / mode / "godot/shared"), "BENCH_OUTPUT": str(output),
           "BENCH_WARMUP": str(args.warmup), "BENCH_DURATION": str(args.duration),
           "BENCH_SCENE" if mode == "scenes" else "BENCH_CASE": item}
    return [str(binary)] + (GODOT_ARGS + ["--disable-vsync"] if engine == "godot" else []), env


def display_env(args):
    env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "LD_PRELOAD")}
    if args.display:
        info = json.loads(Path(args.display).read_text())
        env.update(DISPLAY=info["DISPLAY"], XAUTHORITY=info["XAUTHORITY"])
    env["vblank_mode"] = "0"  # Mesa: no VSync whatever the app asks for
    return env


def launch(cmd, env, output, args):
    """Runs one process until it reports BENCH_MEASURE_END; returns its row and data. Its output goes
    next to the result, as .log, whether the run worked or not."""
    start = time.monotonic()
    while pkg_temp() > args.max_temp and time.monotonic() - start < 600:
        time.sleep(1)
    time.sleep(args.cooldown)
    temp_start = pkg_temp()
    proc = subprocess.Popen(["taskset", "-c", args.cores] + cmd, cwd=Path(cmd[0]).parent, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    log, buf, begin, end, error = bytearray(), b"", None, None, None
    deadline = time.monotonic() + args.warmup + args.duration + 180
    try:
        while time.monotonic() < deadline and error is None:
            for key, _ in sel.select(0.02):
                block = os.read(key.fileobj.fileno(), 65536)
                if not block:
                    sel.unregister(key.fileobj)
                    continue
                log += block
                buf += block
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if b"ERROR" in line or b"is missing" in line or b"terminate called" in line:
                        error = line.decode(errors="replace")
                    if b"BENCH_MEASURE_BEGIN" in line:
                        begin = cpu_seconds(proc.pid)
                    if b"BENCH_MEASURE_END" in line:
                        end = cpu_seconds(proc.pid)
                        rss, peak = status_mib(proc.pid, "VmRSS"), status_mib(proc.pid, "VmHWM")
            if end is not None and output.exists() and output.stat().st_size > 0:
                time.sleep(0.4)
                break
            if proc.poll() is not None and not sel.get_map():
                break
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)  # Godot exports ignore SIGTERM
        proc.wait()
        sel.close()
        output.with_suffix(".log").write_bytes(bytes(log))
    if error:
        raise RuntimeError(error)
    if begin is None or end is None or not output.exists():
        raise RuntimeError("no result")
    data = json.loads(output.read_text())
    row = stats(data["frame_ms"])
    row.update(cpu_ms=1000 * (end - begin) / row["frames"], rss_mib=rss, peak_mib=peak,
               draws=statistics.median(data["draw_calls"]), temp_start=temp_start, temp_end=pkg_temp())
    if "script_ms" in data:
        row["script_ms"] = statistics.fmean(data["script_ms"])
        row["engine_ms"] = row["frame_ms"] - row["script_ms"]
    return row, data


def expected_positions(spec, case, t):
    """Where the objects of a stress test are at time t, None when the engine does not report them."""
    if case["kind"] != "sprites":
        return None if case["instanced"] else [c[:3] for c in spec["cubes"][:case["count"]]]
    m = spec["motion"]
    out = []
    for x, y, phase in spec["sprites"][:case["count"]]:
        if case["moving"]:
            x += m["x_amplitude"] * math.sin(m["angular_speed"] * t + phase)
            y += m["y_amplitude"] * math.cos(m["angular_speed"] * t + phase)
        out.append([x, y, 0])
    return out


def check_suite(data, spec, case):
    """Both engines must have drawn the same objects in the same places."""
    if data["count"] != case["count"] or data["resolution"] != [1280, 720]:
        raise RuntimeError(f"count {data['count']}, resolution {data['resolution']}")
    for t, key in ((0, "positions_t0"), (1, "positions_t1")):
        expected = expected_positions(spec, case, t)
        if expected is None:
            continue
        if len(data[key]) != len(expected):
            raise RuntimeError(f"{key}: {len(data[key])} positions, expected {len(expected)}")
        worst = max(abs(a - b) for g, e in zip(data[key], expected) for a, b in zip(g, e))
        if worst > 2e-3:
            raise RuntimeError(f"{key} off by {worst}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=MODES)
    p.add_argument("--label", default=datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    p.add_argument("--scene", "--level", "--case", dest="items", nargs="+", metavar="NAME",
                   help="the scenes, levels or cases to run (default: all of the mode)")
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--warmup", type=float, help="seconds before measuring (default per mode)")
    p.add_argument("--duration", type=float, help="seconds measured (default per mode)")
    p.add_argument("--cooldown", type=float, default=3, help="seconds of rest before each run")
    p.add_argument("--max-temp", type=float, default=70, help="start a run only below this package temperature")
    p.add_argument("--cores", default="0-5", help="taskset core list, ideally the P-cores")
    p.add_argument("--doriax", type=Path, help="Doriax binary (default: the one build.sh made)")
    p.add_argument("--godot", type=Path, help="Godot export (default: the one build.sh made)")
    p.add_argument("--display", help="display.json written by tools/display.py (default: current DISPLAY)")
    args = p.parse_args()

    mode = MODES[args.mode]
    items = args.items or mode["items"]
    unknown = [i for i in items if i not in mode["items"]]
    if unknown:
        raise SystemExit(f"unknown {', '.join(unknown)}; {args.mode} has: {', '.join(mode['items'])}")
    args.warmup = mode["warmup"] if args.warmup is None else args.warmup
    args.duration = mode["duration"] if args.duration is None else args.duration
    binaries = {"doriax": args.doriax or mode["doriax"], "godot": args.godot or mode["godot"]}
    for binary in binaries.values():
        if not binary.exists():
            raise SystemExit(f"{binary} not found, run build.sh first")
    spec = json.loads((BUILD / "suite/godot/shared/workloads.json").read_text()) if args.mode == "suite" else None
    cases = {c["id"]: c for c in spec["cases"]} if spec else {}
    key = "case" if args.mode == "suite" else "scene"

    out = ROOT / "results" / args.label
    (out / "raw").mkdir(parents=True, exist_ok=True)
    # paths inside the repository are saved relative to it, so published results hold no home folder
    files = {**binaries, **({"display": Path(args.display)} if args.display else {})}
    shown = {k: str(v.resolve().relative_to(ROOT)) if v.resolve().is_relative_to(ROOT) else v.name
             for k, v in files.items()}
    (out / "args.json").write_text(json.dumps({**vars(args), "items": items, **shown}, indent=1))
    env = display_env(args)
    rows = []
    for index in range(args.runs):
        engines = ["doriax", "godot"] if index % 2 == 0 else ["godot", "doriax"]
        for item in (items if index % 2 == 0 else items[::-1]):
            for engine in engines:
                stem = f"{engine}-{item.replace(' ', '-').lower()}-{index}"
                output = out / "raw" / f"{stem}.json"
                cmd, extra = command(args.mode, engine, binaries[engine], item, output, args)
                try:
                    row, data = launch(cmd, {**env, **extra}, output, args)
                    if spec:
                        check_suite(data, spec, cases[item])
                except RuntimeError as e:
                    print(f"FAILED {stem}: {e}", flush=True)
                    rows.append({"engine": engine, key: item, "run": index, "error": str(e)})
                else:
                    rows.append({"engine": engine, key: item, "run": index, **row})
                    print(f"{stem:34s} {row['fps']:8.1f} FPS  1% low {row['low1_fps']:7.1f}  cpu {row['cpu_ms']:.3f} ms"
                          f"  rss {row['rss_mib']:.0f} MiB  {row['temp_start']:.0f}->{row['temp_end']:.0f} C", flush=True)
                (out / "runs.json").write_text(json.dumps(rows, indent=1))
    subprocess.run([sys.executable, str(ROOT / "summary.py"), str(out)])


if __name__ == "__main__":
    main()
