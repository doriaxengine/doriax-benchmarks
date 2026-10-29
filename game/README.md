# Lost Slime 3D in both engines

The Doriax side is the original game, [doriaxengine/lostslime3d](https://github.com/doriaxengine/lostslime3d)
at commit `9be674c`. `build.sh` clones it, exports a copy with the Doriax editor (the export rewrites the
project it reads, so the clone stays untouched), adds `doriax/benchmark.cpp` to the exported project and
turns VSync off before building it in Release.

`godot/` is a port of the same game to Godot 4.7.2 (Compatibility renderer, GDScript, Jolt physics). It is
a complete game you can play: open `godot/project.godot` in Godot and press F5, or start a level directly
with `-- --level "Level One"`.

## How the port was made

`godot/tools/convert.py` copies the original assets and turns the original `.scene` and `.bundle` files into
`godot/data/source.json`. At startup `scene_builder.gd` builds native Godot nodes from that file: meshes,
lights, cameras, physics bodies, areas, UI, sounds and animations. `player.gd` and `game.gd` are the
original C++ game code rewritten in GDScript. Movement constants, capsule size, gravity, platforms, camera
distance and field of view, and pickups all come from the original.

You can check that the port's data and assets match the original byte for byte:

```
git clone https://github.com/doriaxengine/lostslime3d.git
git -C lostslime3d checkout 9be674c
pip install -r godot/tools/requirements.txt
python3 godot/tools/verify_source.py --source lostslime3d
```

It is a faithful port, not a pixel-identical one. Godot uses its own PBR shading, fog, shadows, font
rendering and animation blending. A few settings were chosen to match Doriax:

* Mesh LOD is off in both engines.
* Godot's 4096 x 4096 directional shadow atlas gives each of its four cascades 2048 x 2048 texels, the
  same as Doriax per cascade.
* Doriax divides light intensity by pi and Godot multiplies directional energy by pi, so the benchmark
  runs Godot with `--light-scale 0.32` to get the same light. Run it with `-- --light-scale 1.0` to see the
  authored energy instead.

`godot -- --smoke-test` (headless) plays through both levels with scripted input to check movement,
pickups, keys, checkpoints, damage, pause and the level flow.

## The benchmark

Both engines load a level and fly the camera along the route in `godot/benchmark/routes.json`: 5 seconds
of warm-up, then 20 measured seconds. The game runs as usual (animations, moving platforms, physics), with
nobody at the controls. The Godot side is `godot/scripts/benchmark.gd`, the Doriax side
`doriax/benchmark.cpp`.

## Credits

Models, UI, skyboxes and sounds are CC0 assets by [Kenney](https://kenney.nl): Platformer Kit, UI Pack
Adventure, Mobile Controls, Skyboxes, Interface Sounds, Impact Sounds, Music Jingles and New Platformer
Pack. The Titan One and Sniglet fonts are under the SIL Open Font License. The license files are in
`godot/assets/licenses/`.
