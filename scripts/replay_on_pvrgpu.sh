#!/usr/bin/env bash
# Replay a PVRCarbon recording on the PvrGPU model: PVRCarbonPlayer -> GLVND EGL ->
# PvrGPU Mesa (GALLIUM_DRIVER=pvrgpu) -> SystemC bridge. Environment mirrors the
# pvrgpu backend of PvrGPU's rdc_runner (src/rdc_runner/main.cpp).
#
#   scripts/replay_on_pvrgpu.sh <recording.pvrcbn> [outdir]
#   scripts/replay_on_pvrgpu.sh <tocpp program> [outdir]
#
# A program built by scripts/tocpp_frame.sh (build-headless/) runs in the same
# environment with PBUFFER=1, CAPTURE_PPM=<outdir>/frame.ppm and
# MARK_OUT=<outdir>/marks.txt (set MARK_FRAME to mark frames).
#
# Env:
#   PVRGPU_ENV_ROOT   PvrGPU setup root (script/setup_linux_env.sh)
#   PVRGPU_RUN_MODE   fast (default) | sim
#   CAPTURE_FRAMES    PVRCarbonPlayer frames to save as PNG (default: all)
#   PVRCARBON_DIR     PVRCarbon install dir (default /opt/PVRCarbon)
set -euo pipefail

rec="$(realpath "$1")"
out="$(realpath -m "${2:-out/pvrgpu/$(basename "$rec" .pvrcbn)}")"
if [[ "$rec" == *.pvrcbn ]]; then
  capture=(--capture-frames${CAPTURE_FRAMES:+=$CAPTURE_FRAMES})
  run=("${PVRCARBON_DIR:-/opt/PVRCarbon}/Player/Linux_x86_64/PVRCarbonPlayer" --offscreen
       "${capture[@]}" --capture-frames-path="$out/player-frames" "$rec")
else
  run=(env PBUFFER=1 CAPTURE_PPM="$out/frame.ppm" MARK_OUT="$out/marks.txt" "$rec")
fi
PVRGPU_ENV_ROOT="${PVRGPU_ENV_ROOT:-$HOME/Downloads/_Codex/Working/PvrGPU}"
PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"
# shellcheck disable=SC1091
source "$PVRGPU_ENV_ROOT/env.sh"
mesa="$PVRGPU_MESA_PVRGPU_PREFIX"

rm -rf "$out"
mkdir -p "$out"/{model,player-frames,tmp,xdg-cache}

start=$(date +%s)
set +e
env -u DISPLAY \
  LC_ALL=C TZ=UTC TMPDIR="$out/tmp" XDG_CACHE_HOME="$out/xdg-cache" \
  LD_LIBRARY_PATH="$mesa/lib" \
  __EGL_VENDOR_LIBRARY_FILENAMES="$mesa/share/glvnd/egl_vendor.d/50_mesa.json" \
  EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=swrast \
  MESA_SHADER_CACHE_DISABLE=true MESA_GLES_VERSION_OVERRIDE=3.2 \
  GALLIUM_DRIVER=pvrgpu PVRGPU_RUN_MODE="${PVRGPU_RUN_MODE:-fast}" \
  PVRGPU_SYSTEMC_API_LIB="$PVRGPU_BUILD_DIR/lib/libpvrgpu_systemc_bridge.so" \
  PVRGPU_DRIVER_COMMAND_OUT="$out/driver-command.txt" \
  PVRGPU_DRIVER_COUNTER_OUT="$out/driver-counter.txt" \
  PVRGPU_FRAME_SESSION_OUT="$out/frame-sessions.txt" \
  PVRGPU_FRAME_PLAN_OUT="$out/frame-plan.txt" \
  PVRGPU_SYSTEMC_JSONL_OUT="$out/model.jsonl" \
  PVRGPU_SYSTEMC_STDERR_OUT="$out/model.stderr" \
  PVRGPU_SYSTEMC_OUTDIR="$out/model" \
  "${run[@]}" >"$out/player.log" 2>&1
rc=$?
set -e

echo "exit=$rc wall=$(( $(date +%s) - start ))s out=$out"
grep -E 'ERROR|Finished' "$out/player.log" | head -5 || true
ls "$out/player-frames" "$out/model" 2>/dev/null || true
exit $rc
