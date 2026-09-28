#!/usr/bin/env python3
"""Split PvrGPU's simulated time at frames marked by a tocpp_frame.sh program.

usage: frame_sim_time.py <model.jsonl> <mark file>

Each mark line is "frame bytes": model.jsonl's byte size when that recorded
frame started (after glFinish). virtual_time_ns is cumulative, so a marked
frame took max(before the next mark) - max(before its own mark); the last one
runs to the end of the replay.
"""
import json
import sys

jsonl, mark = sys.argv[1], sys.argv[2]
data = open(jsonl, "rb").read()
marks = [tuple(int(v) for v in line.split()) for line in open(mark) if line.strip()]


def counters(chunk):
    return [json.loads(line).get("virtual_time_ns", 0) for line in chunk.splitlines()
            if line.startswith(b"{") and b'"type":"counter"' in line]


cuts = [(frame, offset) for frame, offset in marks] + [(None, len(data))]
previous = counters(data[:cuts[0][1]])
result = {"before_first_mark": {"submissions": len(previous),
                                "sim_ms": max(previous, default=0) / 1e6}}
for (frame, start), (_, end) in zip(cuts, cuts[1:]):
    upto = counters(data[:end])
    result[f"frame_{frame}"] = {
        "submissions": len(upto) - len(previous),
        "sim_ms": (max(upto, default=0) - max(previous, default=0)) / 1e6,
    }
    previous = upto
result["total_sim_ms"] = max(previous, default=0) / 1e6
print(json.dumps(result, indent=1))
