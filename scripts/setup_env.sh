#!/usr/bin/env bash
# Prepare a headless Linux host for PVRCarbon recording:
# Mesa llvmpipe (EGL / OpenGL ES 3.2) + lavapipe (Vulkan) under Xvfb.
set -euo pipefail

sudo_cmd=""
[ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

$sudo_cmd apt-get update -qq || true
DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq \
  mesa-utils mesa-utils-bin libegl-mesa0 libgles2 libgl1-mesa-dri \
  mesa-vulkan-drivers vulkan-tools xvfb

export DISPLAY="${DISPLAY:-:99}"
if ! pgrep -x Xvfb >/dev/null; then
  Xvfb "$DISPLAY" -screen 0 1920x1080x24 >/dev/null 2>&1 &
  sleep 2
fi

echo "== EGL / GLES =="
eglinfo -B 2>/dev/null | grep -E "OpenGL ES profile (renderer|version)" | head -2
echo "== Vulkan =="
vulkaninfo --summary 2>/dev/null | grep -E "deviceName|apiVersion" | head -2
echo "DISPLAY=$DISPLAY"
