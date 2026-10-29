#!/usr/bin/env python3
"""Writes the twelve stress tests into <out>/shared: workloads.json (positions and phases), four small
checkerboard textures and the key model. Both engines read this folder.

    gen.py <out>
"""
import hashlib
import json
import math
from pathlib import Path
import random
import shutil
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import godot_import  # noqa: E402

MODEL = Path(__file__).resolve().parents[1] / "assets/kenney-platformer-kit/key.glb"


def png(path, colors):
    pixels = bytearray()
    for y in range(16):
        pixels.append(0)
        for x in range(16):
            pixels.extend(colors[(x // 4 + y // 4) % 2])
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 6, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def main():
    shared = Path(sys.argv[1]) / "shared"
    shared.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20261024)
    sprites = [[round(rng.uniform(24, 1256), 4), round(rng.uniform(24, 696), 4),
                round(rng.uniform(0, math.tau), 6)] for _ in range(10000)]
    cubes = [[round((i % 100 - 49.5) * 1.3, 4), round((i // 100 - 24.5) * 1.3, 4),
              round((i % 7 - 3) * 0.15, 4), round(rng.uniform(0, math.tau), 6)] for i in range(5000)]
    ax, ay = math.radians(20) / 2, math.radians(35) / 2
    rotation = [math.sin(ax) * math.cos(ay), math.cos(ax) * math.sin(ay),
                -math.sin(ax) * math.sin(ay), math.cos(ax) * math.cos(ay)]
    cases = [
        dict(id="sprites_static_3000", kind="sprites", count=3000),
        dict(id="sprites_moving_3000", kind="sprites", count=3000, moving=True),
        dict(id="sprites_static_10000", kind="sprites", count=10000),
        dict(id="sprites_moving_10000", kind="sprites", count=10000, moving=True),
        dict(id="sprites_multitex_3000", kind="sprites", count=3000, textures=4),
        dict(id="cubes_static_1000", kind="cubes", count=1000),
        dict(id="cubes_static_3000", kind="cubes", count=3000),
        dict(id="cubes_moving_1000", kind="cubes", count=1000, moving=True),
        dict(id="cubes_lit_1000", kind="cubes", count=1000, lit=True),
        dict(id="cubes_instanced_3000", kind="cubes", count=3000, instanced=True),
        dict(id="models_1000", kind="models", count=1000, lit=True),
        dict(id="models_moving_1000", kind="models", count=1000, lit=True, moving=True),
    ]
    for case in cases:
        for key in ("moving", "instanced", "lit"):
            case.setdefault(key, False)
        case.setdefault("textures", 1)
    data = dict(schema=2, resolution=[1280, 720], background=[0.04, 0.06, 0.09, 1], sprite_size=16,
                motion=dict(x_amplitude=8, y_amplitude=8, angular_speed=2),
                cube_size=1, cube_color=[0.25, 0.65, 0.95, 1], cube_rotation=rotation,
                light=dict(direction=[-0.4, -0.7, -0.6], color=[1, 1, 1], energy=1.0),
                model_scale=3.0,
                camera=dict(position=[0, 0, 160], target=[0, 0, 0], ortho_height=84, near=0.1, far=300),
                sprites=sprites, cubes=cubes, cases=cases)
    manifest = shared / "workloads.json"
    manifest.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    palette = [((245, 180, 60, 255), (60, 150, 230, 255)), ((230, 70, 90, 255), (250, 240, 220, 255)),
               ((90, 200, 120, 255), (30, 60, 40, 255)), ((170, 110, 230, 255), (240, 220, 60, 255))]
    for i, colors in enumerate(palette):
        png(shared / f"sprite{i}.png", colors)
        godot_import.write(shared / f"sprite{i}.png")
    shutil.copyfile(MODEL, shared / "key.glb")
    godot_import.write(shared / "key.glb")
    (shared / "Textures").mkdir(exist_ok=True)
    shutil.copyfile(MODEL.parent / "Textures/colormap.png", shared / "Textures/colormap.png")
    godot_import.write(shared / "Textures/colormap.png", detect_3d=0)
    print("workloads SHA256:", hashlib.sha256(manifest.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
