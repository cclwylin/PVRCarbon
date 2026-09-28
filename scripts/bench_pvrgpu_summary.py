#!/usr/bin/env python3
"""Summarise bench_pvrgpu.sh results as a Markdown table (+ summary.json).

usage: bench_pvrgpu_summary.py <bench_dir> <llvmpipe_reference_png_dir>
"""
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:  # pixel comparison is optional
    Image = None

bench, ref_dir = Path(sys.argv[1]), Path(sys.argv[2])
rows = []
for run in sorted(p for p in bench.glob("*/*") if p.is_dir()):
    mode, test = run.parent.name, run.name
    row = {"mode": mode, "test": test}
    t = run.with_suffix(".time")
    if t.exists():
        wall, rss_kb = t.read_text().split()[-2:]
        row["wall_s"] = float(wall)
        row["peak_rss_gb"] = int(rss_kb) / 1024 / 1024
    log = (run / "player.log").read_text(errors="replace") if (run / "player.log").exists() else ""
    row["player_errors"] = len(re.findall(r"\|ERROR:", log))
    counters = [json.loads(l) for l in (run / "model.jsonl").open() if l.startswith("{")] \
        if (run / "model.jsonl").exists() else []
    counter = [c for c in counters if c.get("type") == "counter"]
    done = [c for c in counters if c.get("type") == "done"]
    row["submissions"] = len(counter)
    # virtual_time_ns is the model's cumulative simulated time at each
    # submission, so the run's total is the last (largest) value.
    row["sim_ms"] = max((c.get("virtual_time_ns", 0) for c in counter), default=0) / 1e6
    row["pool_leaks"] = sum(d.get("pool_leaks", 0) for d in done)
    for k in ("ia_primitives", "setup_triangles", "ps_invocations"):
        row[k] = sum((c.get("counters") or {}).get(k, 0) for c in counter)
    dc = (run / "driver-counter.txt")
    text = dc.read_text(errors="replace") if dc.exists() else ""
    row["unsupported_events"] = len(re.findall(r"event=\S*unsupported", text))
    # The last captured frame is the one measured: frame 1 of a Loading +
    # scene recording, frame 0 of a single-frame (trimmed) one.
    frames = sorted((run / "player-frames").glob(f"{test}_frame_*.png"),
                    key=lambda f: int(f.stem.rsplit("_", 1)[1]))
    frame = frames[-1] if frames else run / "player-frames" / "missing.png"
    ref = ref_dir / f"{test}.png"
    if Image and frame.exists() and ref.exists():
        a, b = Image.open(ref).convert("RGB"), Image.open(frame).convert("RGB")
        if a.size == b.size:
            diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 16 else 0)
            row["diff_px_pct"] = 100 * diff.histogram()[255] / (a.size[0] * a.size[1])
    rows.append(row)

(bench / "summary.json").write_text(json.dumps(rows, indent=1))
cols = [("mode", "mode", "{}"), ("test", "test", "{}"), ("wall_s", "wall (s)", "{:.0f}"),
        ("sim_ms", "sim time (ms)", "{:.2f}"), ("submissions", "submissions", "{}"),
        ("ia_primitives", "IA prims", "{}"), ("ps_invocations", "PS invocations", "{}"),
        ("peak_rss_gb", "peak RSS (GB)", "{:.2f}"), ("player_errors", "player errors", "{}"),
        ("unsupported_events", "unsupported", "{}"), ("pool_leaks", "pool leaks", "{}"),
        ("diff_px_pct", "px diff vs llvmpipe (%)", "{:.2f}")]
print("| " + " | ".join(c[1] for c in cols) + " |")
print("|" + "---|" * len(cols))
for r in rows:
    print("| " + " | ".join(f.format(r[k]) if k in r else "-" for k, _, f in cols) + " |")
