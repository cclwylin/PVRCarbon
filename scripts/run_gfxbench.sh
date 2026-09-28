#!/usr/bin/env bash
# Run GFXBench GLES tests headless (Xvfb + Mesa llvmpipe) with a fixed, small
# number of frames so runs are short and deterministic.
#
#   scripts/run_gfxbench.sh [test_id ...]
#
# Env:
#   FRAMES      frames to render per test        (default 10)
#   STEP_MS     fixed animation step per frame   (default 100)
#   WIDTH/HEIGHT                                  (default 640x360)
#   OUT_DIR     where logs/results go            (default ./out/runs)
#   WRAPPER     command prefix used to launch testfw_app, e.g. a capture tool
set -euo pipefail

GFXBENCH_DIR="${GFXBENCH_DIR:-/home/user/kishonti-opensource/gfxbench}"
FRAMES="${FRAMES:-10}"
STEP_MS="${STEP_MS:-100}"
WIDTH="${WIDTH:-640}"
HEIGHT="${HEIGHT:-360}"
OUT_DIR="$(realpath -m "${OUT_DIR:-out/runs}")"
WRAPPER="${WRAPPER:-}"

# T-Rex, Manhattan 3.0, Manhattan 3.1, Car Chase, Aztec Ruins (normal / high)
tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=(gl_trex gl_manhattan gl_manhattan31 gl_4 gl_5_normal gl_5_high)

export DISPLAY="${DISPLAY:-:99}"
if ! pgrep -x Xvfb >/dev/null; then
  Xvfb "$DISPLAY" -screen 0 1920x1080x24 >/dev/null 2>&1 &
  sleep 2
fi

mkdir -p "$OUT_DIR"
cd "$GFXBENCH_DIR/tfw-pkg"
for t in "${tests[@]}"; do
  log="$OUT_DIR/$t.log"
  start=$(date +%s)
  # shellcheck disable=SC2086
  $WRAPPER ./bin/testfw_app -b . --gfx glfw --gl_api gles -w "$WIDTH" -h "$HEIGHT" -t "$t" \
    --ei -max_rendered_frames="$FRAMES" --ei -frame_step_time="$STEP_MS" >"$log" 2>&1 || true
  status=$(grep -m1 '"status"' "$log" | tr -d ' ",' | cut -d: -f2)
  echo "$t: status=${status:-FAILED} time=$(( $(date +%s) - start ))s log=$log"
done
