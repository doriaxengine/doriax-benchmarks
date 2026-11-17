#!/bin/bash
# Exports the test project with a Doriax 0.8.5 editor and builds the game into build/game.
#
#   EDITOR=~/bin/doriax-editor ./build.sh
#
# EDITOR   the doriax-editor binary of the release to test (its command line exports the project)
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
: "${EDITOR:?set EDITOR to a doriax-editor binary}"
JOBS=${JOBS:-$(nproc)}
rm -rf "$ROOT/build/export"
mkdir -p "$ROOT/build/export"
# the export writes into the project it reads, so it works on a copy
rm -rf "$ROOT/build/project"
cp -r "$ROOT/project" "$ROOT/build/project"
"$EDITOR" export --project "$ROOT/build/project" --out "$ROOT/build/export" --backend opengl
cd "$ROOT/build/export"
python3 doriax.py --platform linux --build --no-debug --graphic-backend glcore --jobs "$JOBS" --output "$ROOT/build/game"
echo "built $ROOT/build/game/LuaVsCpp"
