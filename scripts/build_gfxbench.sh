#!/usr/bin/env bash
# Clone and build the open-source GFXBench 5 (OpenGL / GLES "developer" CLI: testfw_app)
# on Linux. Result: $GFXBENCH_DIR/tfw-pkg/bin/testfw_app
set -euo pipefail

GFXBENCH_DIR="${GFXBENCH_DIR:-/home/user/kishonti-opensource/gfxbench}"
CUDA_HEADERS="${CUDA_HEADERS:-/opt/cuda-headers/include}"

sudo_cmd=""
[ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install --no-install-recommends -y -qq \
  cmake build-essential ninja-build libwayland-dev wayland-protocols libxkbcommon-dev \
  libegl1-mesa-dev libgles2-mesa-dev bison pkg-config libxinerama-dev libxcursor-dev \
  libxrandr-dev libxi-dev libglu1-mesa-dev xorg-dev curl unzip swig python-is-python3 \
  libvulkan-dev python3-pip

if [ ! -d "$GFXBENCH_DIR/.git" ]; then
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 \
    https://github.com/Kishonti-Opensource/gfxbench "$GFXBENCH_DIR"
fi

# frameworks/cudaw only dlopen()s CUDA at runtime, but needs cuda.h to compile.
# Take the headers from the small CUDA runtime wheel instead of the 2.4 GB toolkit.
if [ ! -f "$CUDA_HEADERS/cuda.h" ]; then
  tmp=$(mktemp -d)
  pip download --no-deps -q nvidia-cuda-runtime-cu12==12.4.127 -d "$tmp"
  (cd "$tmp" && unzip -q ./*.whl)
  $sudo_cmd mkdir -p "$(dirname "$CUDA_HEADERS")"
  $sudo_cmd cp -r "$tmp/nvidia/cuda_runtime/include" "$CUDA_HEADERS"
  rm -rf "$tmp"
fi

cd "$GFXBENCH_DIR"
# Same as the repo's CI "linux_gl" job.
sed -i 's/^PRODUCT_ID="gfxbench"$/PRODUCT_ID="gfxbench_gl"/' product
export PLATFORM=linux CONFIG=Release APPLICATION_TYPE=developer
export MAKEFLAGS="-j$(nproc)" CPATH="$CUDA_HEADERS${CPATH:+:$CPATH}"

./scripts/build-3rdparty.sh
./scripts/build.sh

ls -l tfw-pkg/bin/testfw_app
