# Lua vs C++ in Doriax 0.8.5

The same game code written twice, once as Lua scripts and once as C++ scripts, in one Doriax
project, and timed in exported release builds. Each round spawns the same objects in both languages
and runs the same logic, line for line.

| Round | What the scripts do | Lua 5.5 (ms) | C++ (ms) | C++ faster |
| --- | --- | ---: | ---: | ---: |
| Arena | a player and 100 enemies, one script each: chase the player, keep a place around it | 0.211 | 0.010 | 20.5× |
| Crowd | 10 000 cubes, one script each: read the position, move up and down, turn | 16.72 | 1.54 | 10.9× |
| Paths | one script: A* on a 72 × 40 grid, 80 searches a frame for 400 agents, then moves them | 4.15 | 0.50 | 8.3× |
| Rays | one script: 2 000 raycasts a frame against 160 static bodies, a point moved to each hit | 9.20 | 1.04 | 8.8× |

Script time per frame: the median of the five runs' medians, in CPU time of the game's main thread.
A frame at 60 fps has 16.7 ms. Measured on an Intel Core i7-12700T (desktop, 35 W), Ubuntu 26.04,
Linux 7.0, GCC 15, Doriax 0.8.5 (tag `v0.8.5`, commit `c28c25d9`) with its Lua 5.5.1.

## How it is timed

`Bench` (C++, in every round scene) spawns the round's bundles: the Lua ones, the C++ ones, or the
ones with no script, as `BENCH_LANG` says. Its `onUpdate` runs first in every frame, because it
subscribed first; after spawning it adds a second `onUpdate` callback, which runs after every
script's. The time between the two is the script time of that frame: every script's `onUpdate`, and
nothing of the engine's own update or of the drawing. `Bench` keeps 600 frames after 120 frames of
warm-up and writes them to `BENCH_OUT`, wall time and CPU time of the thread both.

`bench.py` runs every round in the three versions five times, alternating the order, pinned to six
performance cores (one thread each), each run after the CPU load fell under 6. The drawing goes
through Mesa's no-op driver (`GALLIUM_NOOP=1`): the GPU never limits a frame, and the scripts do not
depend on it. Run to run, the medians stayed within 9% of each other.

The Paths and Rays scripts move their simulation by a fixed 1/60 s a frame, so every run makes the
same searches and casts the same rays; Arena and Crowd move by the frame's time, and do the same work
in every frame whatever its length.

## Running it

You need Linux with X11 (or Xvfb), Python 3, CMake and a C++ compiler, and the Doriax 0.8.5 editor
binary (its command line exports the project).

```
EDITOR=~/bin/doriax-editor ./build.sh
python3 bench.py run --label mine --cores 0,2,4,6,8,10
python3 bench.py summary --label mine
```

Pick `--cores` to match your CPU: one logical CPU per performance core.

## The project

`project/` is the editor project: `scenes/` (Boot loads the scene named by `BENCH_SCENE`), the
bundles in `assets/`, the Lua scripts in `lua/` and the C++ ones in `scripts/`. The C++ sources sit
in a script directory of the project (`scriptDirs: [scripts]`), so that the scripts only standalone
bundles use are compiled into the export too.

`results/0.8.5-i7-12700T/` has every run: `<Round>-<lua|cpp|off>-<run>.json` with the frame times,
`runs.json` and `summary.json`.
