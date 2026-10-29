# Doriax benchmarks

Performance tests of [Doriax](https://github.com/doriaxengine/doriax) against other engines, with
everything needed to run them yourself: the test projects for each engine, the build and run scripts,
and the raw data of every published run.

| Benchmark | Results |
| --- | --- |
| Doriax 0.8.4 vs Godot 4.7.2 (October 2026) | [results/0.8.4-vs-godot-4.7.2](results/0.8.4-vs-godot-4.7.2) |

## Doriax 0.8.4 vs Godot 4.7.2

Medians of five runs, 1280 x 720, OpenGL, VSync off, on an Intel Core Ultra 9 285H laptop with
integrated graphics.

| Test | Doriax FPS | Godot FPS | Doriax / Godot |
| --- | ---: | ---: | ---: |
| Lost Slime 3D, Level One | 1 055 | 865 | 1.22 |
| Lost Slime 3D, Level Two | 1 181 | 928 | 1.27 |
| 16 000 sprites | 2 194 | 1 260 | 1.74 |
| 4 245 lit models | 529 | 387 | 1.37 |
| 12 stress tests | | | 1.34 to 2.15 |

The [results folder](results/0.8.4-vs-godot-4.7.2) has the method, the full tables with 1% lows, CPU
time and memory, and every run.

## What is in here

* `game/`: Lost Slime 3D, a Doriax game, and its port to Godot. A camera flies the same route in both.
* `scenes/`: 16 000 sprites with a scrolling camera, and an island of 4 245 lit models.
* `suite/`: twelve small stress tests with sprites, cubes and models.
* `results/`: every run of each published benchmark.

## Running it

You need Linux with X11 or Xwayland, Python 3, git, rsync, the
[Doriax build dependencies](https://docs.doriax.org/building/linux/), and
[Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) with its export templates.

```
git clone --branch v0.8.4 https://github.com/doriaxengine/doriax.git ~/src/doriax
DORIAX=~/src/doriax GODOT=~/bin/Godot_v4.7.2-stable_linux.x86_64 ./build.sh

python3 run.py game --label mine/game
python3 run.py scenes --label mine/scenes
python3 run.py suite --label mine/suite
python3 summary.py results/mine/*
```

Runs are pinned to cores 0-5 (`--cores`), the performance cores of my CPU, so change that to match
yours. Close other programs while it runs. The 0.8.4 sprite numbers come from
`run.py scenes --scene crowd --cooldown 60`, see the results notes for why. `python3 run.py --help` lists
the options.

## License

The code is MIT. The art is CC0 by [Kenney](https://kenney.nl) and the fonts are under the SIL Open Font
License, with their license files next to them. Godot is a trademark of the Godot Foundation, and this
project is not affiliated with it.
