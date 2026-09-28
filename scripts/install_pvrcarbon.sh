#!/usr/bin/env bash
# Download and install the PVRCarbon Linux package from Imagination's developer site.
# Running this accepts the PowerVR Tools EULA (--skip-license):
#   https://developer.imaginationtech.com/terms/
set -euo pipefail

PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"
PVRCARBON_URL="${PVRCARBON_URL:-https://pvr-sdk-live.s3.us-east-1.amazonaws.com/sdk/OFFLINE/PVRCarbonSetup-2026_R2.sh}"
DL_DIR="${DL_DIR:-/home/user/pvrcarbon-dl}"

if [ -x "$PVRCARBON_DIR/CLI/Linux_x86_64/PVRCarbonDump" ]; then
  echo "PVRCarbon already installed in $PVRCARBON_DIR"
  exit 0
fi

sudo_cmd=""
[ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

installer="$DL_DIR/$(basename "$PVRCARBON_URL")"
mkdir -p "$DL_DIR"
[ -f "$installer" ] || curl -fL --retry 3 -o "$installer" "$PVRCARBON_URL"   # ~1.9 GB

$sudo_cmd mkdir -p "$PVRCARBON_DIR"
$sudo_cmd sh "$installer" --prefix="$PVRCARBON_DIR" --skip-license --exclude-subdir
ls "$PVRCARBON_DIR"
