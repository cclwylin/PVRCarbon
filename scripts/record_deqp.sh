#!/usr/bin/env bash
# Record dEQP GLES cases with the PVRCarbon recorder, one .pvrcbn per case.
#
#   scripts/record_deqp.sh <caselist>
#
# The cases run on the host GLES (Mesa llvmpipe) through the recorder's
# EGL/GLES libraries, with PvrGPU's dEQP defaults: a 256x256 pbuffer and
# rgba8888d24s8ms0. Each case's dEQP verdict is kept next to its recording.
#
# Env:
#   DEQP_BUILD      VK-GL-CTS build dir with modules/<module>/deqp-<module>
#                   (default /home/user/deqp-build)
#   REC_DIR         output dir                     (default out/deqp)
#   PVRCARBON_DIR   PVRCarbon install dir          (default /opt/PVRCarbon)
#   TIMEOUT         seconds per case               (default 600)
set -euo pipefail

caselist="$(realpath "$1")"
DEQP_BUILD="$(realpath "${DEQP_BUILD:-/home/user/deqp-build}")"
REC_DIR="$(realpath -m "${REC_DIR:-out/deqp}")"
PVRCARBON_DIR="${PVRCARBON_DIR:-/opt/PVRCarbon}"
recorder="$PVRCARBON_DIR/Recorder/GLES/Linux_x86_64"
libdir=/usr/lib/x86_64-linux-gnu

mkdir -p "$REC_DIR"
display=":$((90 + RANDOM % 9))"
Xvfb "$display" -screen 0 640x480x24 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
trap 'kill $xvfb 2>/dev/null' EXIT
sleep 1

summary="$REC_DIR/summary.tsv"
printf 'case\tverdict\texit\tseconds\tbytes\n' > "$summary"
while read -r case; do
  [[ -z "$case" || "$case" == \#* ]] && continue
  module="$(tr '[:upper:]' '[:lower:]' <<<"${case%%.*}")"; module="${module#deqp-}"
  bin_dir="$DEQP_BUILD/modules/$module"
  rec="$REC_DIR/$case.pvrcbn"
  qpa="$REC_DIR/$case.qpa"
  rm -rf "$rec" "$rec".*.parts "$qpa"
  start=$(date +%s)
  set +e
  (cd "$bin_dir" && env DISPLAY="$display" \
    LD_LIBRARY_PATH="$recorder${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    PVRCARBON_host_library_egl="$libdir/libEGL.so.1" \
    PVRCARBON_host_library_glesv2="$libdir/libGLESv2.so.2" \
    LD_PRELOAD="$recorder/libEGL.so.1:$recorder/libGLESv2.so.2:$recorder/libPVRCarbon.so" \
    PVRCARBON_filename="$rec" \
    timeout "${TIMEOUT:-600}" "./deqp-$module" \
      --deqp-case="$case" --deqp-archive-dir=. \
      --deqp-log-filename="$qpa" --deqp-log-images=disable \
      --deqp-surface-type=pbuffer --deqp-surface-width=256 --deqp-surface-height=256 \
      --deqp-gl-config-name=rgba8888d24s8ms0 >"$REC_DIR/$case.log" 2>&1)
  rc=$?
  set -e
  # dEQP resets GL state after each case with calls PVRCarbonPlayer does not
  # implement (glDisableiOES, glPrimitiveBoundingBoxEXT). Cut the recording
  # just before the first of them when that is after the case's last draw;
  # otherwise keep it whole and say so in the log.
  if [[ -s "$rec" ]]; then
    txt="$REC_DIR/.calls.txt"
    "$PVRCARBON_DIR/CLI/Linux_x86_64/PVRCarbonToTxt" --export-uids=true -o="$txt" "$rec" >/dev/null 2>&1
    cut_uid="$(grep -m1 -oE '^#[0-9]+ .*(glDisableiOES|glEnableiOES|glPrimitiveBoundingBoxEXT)\(' "$txt" \
      | grep -oE '^#[0-9]+' | tr -d '#' || true)"
    last_draw="$(grep -E '^#[0-9]+ .*glDraw(Arrays|Elements|RangeElements)' "$txt" \
      | tail -1 | grep -oE '^#[0-9]+' | tr -d '#' || true)"
    rm -f "$txt"
    if [[ -n "$cut_uid" && ( -z "$last_draw" || "$cut_uid" -gt "$last_draw" ) ]]; then
      (cd "$REC_DIR" && DISPLAY="$display" "$PVRCARBON_DIR/CLI/Linux_x86_64/PVRCarbonTrim" \
        --uid-range="0-$((cut_uid - 1))" -o="$case.cut" "$rec" >/dev/null 2>&1) &&
        mv "$REC_DIR/$case.cut.pvrcbn" "$rec"
      rm -rf "$REC_DIR/$case.cut"*
    elif [[ -n "$cut_uid" ]]; then
      echo "reset call at uid $cut_uid precedes the last draw ($last_draw); kept whole" >> "$REC_DIR/$case.log"
    fi
  fi
  verdict="$(grep -oE 'StatusCode="[A-Za-z]+"' "$qpa" 2>/dev/null | head -1 | cut -d'"' -f2)"
  bytes=$(stat -c %s "$rec" 2>/dev/null || echo 0)
  printf '%s\t%s\t%s\t%s\t%s\n' "$case" "${verdict:-none}" "$rc" \
    "$(( $(date +%s) - start ))" "$bytes" >> "$summary"
  echo "$case ${verdict:-none} exit=$rc $(( bytes / 1024 )) KB"
done < "$caselist"
