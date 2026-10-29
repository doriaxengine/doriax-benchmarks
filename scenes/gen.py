#!/usr/bin/env python3
"""Writes the two scenes into <out>/shared: scenes.json, the sprite atlas, the models, and Godot import
settings that do the same work as Doriax (no LODs, no shadow meshes, no vertex compression, lossless
textures without mipmaps). Both engines read this folder.

    gen.py <out>
"""
import json
import math
import random
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import godot_import  # noqa: E402

ASSETS = Path(__file__).resolve().parents[1] / "assets"
LS2D = ASSETS / "kenney-new-platformer-pack"
LS3D = ASSETS / "kenney-platformer-kit"

# 2D: a crowd of creatures in a world of 4 x 3 screens, the camera pans over it
WORLD2D = (5120, 2160)
SPRITES = 16000
SIZES = (24, 32, 40, 48)
# 3D: a floating island of grass blocks with props, the camera circles it
TILE = 2.0
ISLAND = 56.0
PROPS = [("grass", 0.30), ("flowers", 0.18), ("tree", 0.12), ("tree-pine", 0.10), ("rocks", 0.08),
         ("mushrooms", 0.06), ("stones", 0.05), ("coin-gold", 0.05), ("plant", 0.05), ("crate", 0.03),
         ("barrel", 0.03), ("tree-pine-small", 0.05)]


def noise(x, z, seed):
    """Smooth value noise in [0, 1] from a few sines, the same on every machine."""
    r = random.Random(seed)
    v = 0.0
    for _ in range(4):
        fx, fz, p = r.uniform(0.03, 0.09), r.uniform(0.03, 0.09), r.uniform(0, math.tau)
        v += math.sin(x * fx + p) * math.cos(z * fz - p)
    return 0.5 + v / 8


def world2d(rng):
    frames = [[int(s.get(k)) for k in ("x", "y", "width", "height")]
              for s in ET.parse(LS2D / "enemies.xml").getroot().iter("SubTexture")]
    w, h = WORLD2D
    sprites = []
    for _ in range(SPRITES):
        size = rng.choice(SIZES)
        sprites.append([round(rng.uniform(size, w - size), 2), round(rng.uniform(size, h - size), 2),
                        size, rng.randrange(len(frames))])
    return {"world": [w, h], "atlas": "enemies.png", "atlas_size": [519, 519], "frames": frames,
            "sprites": sprites, "background": [0.73, 0.87, 0.95, 1.0],
            # camera top-left corner: center + amplitude * sin(2 pi * freq * t / period)
            "camera": {"center": [(w - 1280) / 2, (h - 720) / 2], "amplitude": [1400, 520], "freq": [1, 2],
                       "period": 20.0}}


def world3d(rng):
    models, cells = [], int(ISLAND / TILE)
    names = [p for p, _ in PROPS]
    weights = [w for _, w in PROPS]
    for i in range(-cells, cells + 1):
        for k in range(-cells, cells + 1):
            x, z = i * TILE, k * TILE
            edge = ISLAND * (0.86 + 0.14 * noise(x, z, 7))
            if math.hypot(x, z) > edge:
                continue
            y = round(noise(x, z, 11) * 3) * 0.5 - 0.5
            models.append(["block-grass-large", x, y, z, 90 * rng.randrange(4), 1.0])
            for _ in range(rng.choice((0, 1, 1, 1, 2))):
                name = rng.choices(names, weights)[0]
                px, pz = x + rng.uniform(-0.7, 0.7), z + rng.uniform(-0.7, 0.7)
                models.append([name, round(px, 3), y + 1.0, round(pz, 3), round(rng.uniform(0, 360), 2),
                               round(rng.uniform(0.9, 1.3), 3)])
    return {"models": models, "background": [0.55, 0.75, 0.95, 1.0],
            "light": {"direction": [-0.45, -0.75, -0.5], "color": [1.0, 0.97, 0.92], "intensity": 4.0},
            "ambient": {"color": [0.9, 0.95, 1.0], "intensity": 0.45},
            # the camera circles the island looking at its middle
            "camera": {"radius": 40.0, "height": 22.0, "target": [0, 0, 0], "start_deg": 200.0,
                       "deg_per_s": 6.0, "yfov": 50.0, "near": 0.5, "far": 300.0}}


def main():
    shared = Path(sys.argv[1]) / "shared"
    shared.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20261027)
    scenes = {"schema": 1, "resolution": [1280, 720], "crowd": world2d(rng), "island": world3d(rng)}
    (shared / "scenes.json").write_text(json.dumps(scenes, separators=(",", ":")) + "\n")
    shutil.copyfile(LS2D / "enemies.png", shared / "enemies.png")
    godot_import.write(shared / "enemies.png")
    (shared / "Textures").mkdir(exist_ok=True)
    shutil.copyfile(LS3D / "Textures/colormap.png", shared / "Textures/colormap.png")
    godot_import.write(shared / "Textures/colormap.png", detect_3d=0)
    for name in {m[0] for m in scenes["island"]["models"]}:
        shutil.copyfile(LS3D / f"{name}.glb", shared / f"{name}.glb")
        godot_import.write(shared / f"{name}.glb")
    n3 = len(scenes["island"]["models"])
    print(f"crowd: {SPRITES} sprites; island: {n3} models "
          f"({sum(1 for m in scenes['island']['models'] if m[0] == 'block-grass-large')} blocks)")


if __name__ == "__main__":
    main()
