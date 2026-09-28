#!/usr/bin/env bash
# Replay the 30 s GFXBench recordings on PvrGPU in each run mode and summarise.
#
#   scripts/bench_pvrgpu.sh [test_id ...]
#
# Env:
#   MODES     run modes to use            (default "fast sim")
#   REC_DIR   .pvrcbn recordings          (default out/at30)
#   BENCH_DIR where results go            (default out/pvrgpu-bench)
#   JOBS      replays run concurrently    (default 2; sim can take ~4 GB RSS each)
#   REF_DIR   llvmpipe reference frames   (default docs/at30s)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
MODES="${MODES:-fast sim}"
REC_DIR="$(realpath -m "${REC_DIR:-out/at30}")"
BENCH_DIR="$(realpath -m "${BENCH_DIR:-out/pvrgpu-bench}")"
JOBS="${JOBS:-2}"

tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=(gl_trex gl_manhattan gl_manhattan31 gl_4 gl_5_normal gl_5_high)

mkdir -p "$BENCH_DIR"
for mode in $MODES; do
  for t in "${tests[@]}"; do
    echo "$mode $t"
  done
done | xargs -P "$JOBS" -L 1 sh -c '
  mode=$0 t=$1 out="'"$BENCH_DIR"'/$mode/$t"
  mkdir -p "$(dirname "$out")"
  PVRGPU_RUN_MODE=$mode /usr/bin/time -f "%e %M" -o "$out.time" \
    "'"$here"'/replay_on_pvrgpu.sh" "'"$REC_DIR"'/$t.pvrcbn" "$out" >/dev/null 2>&1
  echo "$mode $t exit=$? $(cat "$out.time" 2>/dev/null | tail -1)"
'

python3 "$here/bench_pvrgpu_summary.py" "$BENCH_DIR" "${REF_DIR:-$here/../docs/at30s}"
