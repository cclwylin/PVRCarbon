#!/usr/bin/env bash
# Record GFXBench GLES tests with the PVRCarbon recorder (one .pvrcbn per test).
#
#   scripts/record_gfxbench.sh [test_id ...]
#
# Env: same as run_gfxbench.sh (FRAMES, STEP_MS, WIDTH, HEIGHT), plus
#   REC_DIR         where .pvrcbn recordings go   (default ./out/recordings)
#   PVRCARBON_DIR   PVRCarbon install dir          (default /opt/PVRCarbon)
#   REC_FRAMES      record only these frames (PVRCARBON_frames, e.g. 2); the
#                   recorder snapshots the GL state at the first one
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"
REC_DIR="$(realpath -m "${REC_DIR:-out/recordings}")"
recorder="$PVRCARBON_DIR/Recorder/GLES/Linux_x86_64"
libdir=/usr/lib/x86_64-linux-gnu

tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=(gl_trex gl_manhattan gl_manhattan31 gl_4 gl_5_normal gl_5_high)

mkdir -p "$REC_DIR"
shim="$REC_DIR/glx_to_carbon.so"
cc -shared -fPIC -O2 -o "$shim" "$here/glx_to_carbon.c" -ldl

for t in "${tests[@]}"; do
  rm -f "$REC_DIR/$t.pvrcbn"
  # The recorder hooks EGL/GLES only, so use --gfx egl (glfw would create a GLX context).
  # PVRCarbon's libEGL/libGLESv2 shadow Mesa's and forward to the host libs. They are also
  # preloaded because testfw_app links libGL (GLVND) directly, and glx_to_carbon.so routes
  # GLEW's glXGetProcAddress lookups to the recorder.
  WRAPPER="env LD_LIBRARY_PATH=$recorder${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
PVRCARBON_host_library_egl=$libdir/libEGL.so.1 \
PVRCARBON_host_library_glesv2=$libdir/libGLESv2.so.2 \
LD_PRELOAD=$shim:$recorder/libEGL.so.1:$recorder/libGLESv2.so.2:$recorder/libPVRCarbon.so \
PVRCARBON_filename=$REC_DIR/$t.pvrcbn${REC_FRAMES:+ PVRCARBON_frames=$REC_FRAMES}" \
  GFX=egl OUT_DIR="${OUT_DIR:-$REC_DIR/logs}" "$here/run_gfxbench.sh" "$t"
  if [ -f "$REC_DIR/$t.pvrcbn" ]; then
    echo "  -> $REC_DIR/$t.pvrcbn ($(du -h "$REC_DIR/$t.pvrcbn" | cut -f1))"
  else
    echo "  -> no recording produced"
  fi
done
