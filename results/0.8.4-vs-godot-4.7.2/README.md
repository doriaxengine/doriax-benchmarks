# Doriax 0.8.4 vs Godot 4.7.2

Doriax 0.8.4 (commit `930133b`, built with GCC 15.2) against the official Godot 4.7.2 build, on a laptop
with an Intel Core Ultra 9 285H, Arc 140T integrated graphics and 32 GB of RAM, running Ubuntu 26.04
(Linux 7.0, Mesa 26.0.8), plugged in, in the "balanced" power profile.

Both engines are release builds drawing with OpenGL (Godot's Compatibility renderer) in a 1280 x 720
window with VSync off. Each test ran five times, alternating which engine went first, pinned to the six
performance cores, and each run started once the CPU was below 70 C. The numbers are medians.

| Test | Doriax FPS | Godot FPS | Doriax / Godot | 1% low | CPU per frame (ms) | Memory (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Lost Slime 3D, Level One | 1 055 | 865 | 1.22 | 521 / 378 | 0.79 / 1.24 | 254 / 205 |
| Lost Slime 3D, Level Two | 1 181 | 928 | 1.27 | 610 / 393 | 0.72 / 1.11 | 222 / 205 |
| 16 000 sprites | 2 194 | 1 260 | 1.74 | 1 038 / 453 | 0.42 / 0.69 | 511 / 213 |
| 4 245 lit models | 529 | 387 | 1.37 | 383 / 197 | 2.63 / 3.97 | 238 / 189 |

| Stress test | Doriax FPS | Godot FPS | Doriax / Godot |
| --- | ---: | ---: | ---: |
| 3 000 sprites | 2 931 | 2 047 | 1.43 |
| 3 000 moving sprites * | 2 585 | 1 242 | 2.08 |
| 10 000 sprites | 2 063 | 1 286 | 1.60 |
| 10 000 moving sprites * | 494 | 306 | 1.61 |
| 3 000 sprites, 4 textures | 713 | 531 | 1.34 |
| 1 000 cubes | 1 778 | 1 210 | 1.47 |
| 3 000 cubes | 869 | 405 | 2.15 |
| 1 000 rotating cubes * | 1 493 | 820 | 1.82 |
| 1 000 lit cubes | 1 760 | 1 175 | 1.50 |
| 3 000 instanced cubes | 3 363 | 2 200 | 1.53 |
| 1 000 models | 1 818 | 1 183 | 1.54 |
| 1 000 rotating models * | 1 275 | 775 | 1.64 |

The pairs are Doriax / Godot. The 1% low is the FPS of the slowest 1% of frames. In the tests marked
with *, the motion is game code: C++ in Doriax and GDScript in Godot. `python3 summary.py
results/0.8.4-vs-godot-4.7.2/*` prints these tables from the raw runs, including 1% lows, CPU time and
memory of the stress tests.

## Notes

The game is the same in both engines: same models, levels, lights, shadows and camera route. See
[game/](../../game) for how the port was made. In the scenes and the suite, both engines read the same
generated data and Godot's import is set to do the same work as Doriax (no LODs, no shadow meshes,
lossless textures).

Godot uses less memory in the game, the sprites and the island. Doriax keeps each component type in an
array of fixed-size blocks reserved up front, so frames never allocate, and that costs some memory. In
the 3D stress tests Doriax uses less.

The 16 000 sprites were measured twice. In the first session (`scenes/`), the Doriax runs dropped from
about 2 250 to 1 280 FPS after 5 to 10 seconds: the laptop sustains only 22 W in the balanced profile,
and with 3 seconds between runs it cut the clocks once the earlier runs had used up the boost. Godot
leaves the GPU partly idle in this test and never hit the limit. So I measured it again with 60 seconds
of rest before each run (`crowd-rested/`, the numbers above). No run was cut, and Godot came out 6% lower
than in the first session. The "performance" profile was not used because it made Godot 15% slower here.

## Files

Each folder has `runs.json` (one row per run), `args.json` (the `run.py` settings) and `raw/` with the
frame times and output of every run. The object positions the stress tests save for checking were
removed from `suite/raw` to keep the repository small.
