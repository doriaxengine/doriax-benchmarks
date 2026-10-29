#!/bin/bash
# Builds everything run.py needs into build/.
#
#   DORIAX=~/src/doriax GODOT=~/bin/Godot_v4.7.2-stable_linux.x86_64 ./build.sh [editor|scenes|suite|game ...]
#
# DORIAX     a checkout of github.com/doriaxengine/doriax (tag v0.8.4)
# GODOT      the official Godot 4.7.2 Linux binary, with the 4.7.2 export templates installed
# EDITOR     an existing doriax-editor binary of the same version (default: built into build/editor)
# LOSTSLIME  a checkout of github.com/doriaxengine/lostslime3d (default: cloned into build/lostslime3d)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
B=$ROOT/build
: "${DORIAX:?set DORIAX to a Doriax checkout}"
: "${GODOT:?set GODOT to the Godot 4.7.2 binary}"
EDITOR=${EDITOR:-$B/editor/doriax-editor}
LOSTSLIME=${LOSTSLIME:-$B/lostslime3d}
LOSTSLIME_COMMIT=9be674cdb0dd486e6fa0ef39e30bb7b4ff65281f
JOBS=${JOBS:-$(nproc)}
WINDOW="-DDORIAX_WINDOW_WIDTH=1280 -DDORIAX_WINDOW_HEIGHT=720 -DDORIAX_WINDOW_RESIZABLE=OFF -DDORIAX_VSYNC_ENABLED=OFF"
# precompiled OpenGL shaders the scenes and the suite draw with
SHADERS="blit depth depth:Tex,Ams mesh:Puc,Nor,Tan,Aop mesh:Puc,Nor,Tan,Aop,Dlo mesh:Puc,Nor,Vc4 mesh:Puc,Nor,Vc4,Dlo
    mesh:Ult,Uv1,Ski,Aop mesh:Ult,Uv1,Uv2,Ski,Aop mesh:Ult,Uv1,Vc4,Txr mesh:Ult,Uv1,Vc4,Txr,Ams mesh:Ult,Uv1,Vc4,Txr,Aop
    mesh:Ult,Uv1,Vc4,Txr,Fog mesh:Ult,Vc4 mesh:Ult,Vc4,Ist mesh:Uv1,Puc,Nor,Tan,Aop mesh:Uv1,Puc,Nor,Tan,Aop,Dlo
    ui:Tex,Vc4 underwater water"
mkdir -p "$B"

step() { echo "== $*"; }

editor() {
    [ -x "$EDITOR" ] && return
    step "Doriax editor"
    cmake -S "$DORIAX" -B "$B/editor" -DCMAKE_BUILD_TYPE=Release > "$B/editor.log"
    cmake --build "$B/editor" -j "$JOBS" >> "$B/editor.log"
}

# a small Doriax program (scenes or suite), its Godot twin and the files both read
pair() {
    local name=$1
    step "$name: data"
    rm -rf "$B/$name/godot"
    mkdir -p "$B/$name/godot"
    cp "$ROOT/$name/godot/"* "$B/$name/godot/"
    python3 "$ROOT/$name/gen.py" "$B/$name/godot"

    step "$name: Doriax"
    cmake -S "$DORIAX/engine" -B "$B/$name/doriax" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ROOT="$ROOT/$name/doriax" \
        -DAPP_NAME="doriax-$name" -DGRAPHIC_BACKEND=glcore $WINDOW > "$B/$name/doriax.log"
    cmake --build "$B/$name/doriax" -j "$JOBS" >> "$B/$name/doriax.log"
    mkdir -p "$B/$name/doriax/assets/shaders"
    "$EDITOR" shaders --out "$B/$name/doriax/assets/shaders" --backend opengl \
        $(for s in $SHADERS; do echo --shader "$s"; done) >> "$B/$name/doriax.log" 2>&1

    step "$name: Godot"
    mkdir -p "$B/$name/godot-export"
    "$GODOT" --headless --path "$B/$name/godot" --import > "$B/$name/godot.log" 2>&1 || true
    "$GODOT" --headless --path "$B/$name/godot" --export-release "Linux Release" "$B/$name/godot-export/$name.x86_64" \
        >> "$B/$name/godot.log" 2>&1
}

game() {
    if [ ! -d "$LOSTSLIME" ]; then
        step "game: cloning Lost Slime 3D"
        git clone -q https://github.com/doriaxengine/lostslime3d.git "$LOSTSLIME"
    fi
    git -C "$LOSTSLIME" -c advice.detachedHead=false checkout -q "$LOSTSLIME_COMMIT"

    # the export writes into the project it reads, so it gets a copy
    step "game: Doriax export"
    rm -rf "$B/game/project" "$B/game/source"
    mkdir -p "$B/game"
    rsync -a --exclude=.git --exclude=workspaces --exclude=.doriax "$LOSTSLIME/" "$B/game/project/"
    "$EDITOR" export --project "$B/game/project" --out "$B/game/source" --backend opengl > "$B/game/doriax.log" 2>&1
    cp "$ROOT/game/doriax/benchmark.cpp" "$ROOT/game/doriax/ProjectBuild.cmake" "$B/game/source/project/"
    sed -i 's/set(DORIAX_VSYNC_ENABLED ON)/set(DORIAX_VSYNC_ENABLED OFF)/' "$B/game/source/CMakeLists.txt"
    step "game: Doriax build"
    cmake -S "$B/game/source" -B "$B/game/doriax" -DCMAKE_BUILD_TYPE=Release >> "$B/game/doriax.log"
    cmake --build "$B/game/doriax" -j "$JOBS" >> "$B/game/doriax.log"

    step "game: Godot"
    mkdir -p "$B/game/godot-export"
    "$GODOT" --headless --path "$ROOT/game/godot" --import > "$B/game/godot.log" 2>&1 || true
    "$GODOT" --headless --path "$ROOT/game/godot" --export-release "Linux Release" \
        "$B/game/godot-export/LostSlime3D.x86_64" >> "$B/game/godot.log" 2>&1
}

targets=${*:-scenes suite game}
editor
for t in $targets; do
    case $t in
        editor) ;;
        scenes|suite) pair "$t" ;;
        game) game ;;
        *) echo "unknown target $t"; exit 1 ;;
    esac
done
echo "done, logs are in build/"
