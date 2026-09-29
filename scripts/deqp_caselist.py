#!/usr/bin/env python3
"""Print the dEQP cases PvrGPU's four-level plan runs for some groups.

usage: deqp_caselist.py <discovery caselist> [--tier L1] [--groups 9,10,25,26]

The discovery caselist is what `deqp-<module> --deqp-runmode=txt-caselist`
exports ("TEST: dEQP-..." lines, or bare names). Sampling, quotas and the
L4-only exclusions come from PvrGPU's script/deqp_4level_catalog.py
($PVRGPU_REPO, default ~/pvrgpu or /home/user/pvrgpu), so the list is the
same one `script/run_deqp_level.sh` would run.
"""
import argparse
import os
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("discovery", type=Path)
parser.add_argument("--tier", default="L1")
parser.add_argument("--groups", default="9,10,25,26",
                    help="group numbers (default: the GLES3 shader groups)")
args = parser.parse_args()

repo = Path(os.environ.get("PVRGPU_REPO") or
            next((p for p in (Path.home() / "pvrgpu", Path("/home/user/pvrgpu"))
                  if p.is_dir()), Path("pvrgpu")))
sys.path.insert(0, str(repo / "script"))
import deqp_4level_catalog as catalog  # noqa: E402

cases = []
for line in args.discovery.read_text().splitlines():
    line = line.strip()
    if line.startswith("TEST:"):
        line = line[5:].strip()
    if line.startswith("dEQP-"):
        cases.append(line)

groups = [catalog.GROUPS_BY_NUMBER[int(n)] for n in args.groups.split(",")]
discovery = {}
for case in cases:
    discovery.setdefault(catalog.module_for_case(case), []).append(case)
plan = catalog.build_plan(
    name="pvrcarbon", tier=catalog.TIERS_BY_ID[args.tier], groups=groups,
    discovery=discovery, shards=1, log_images="disable",
    default_config=catalog.DEFAULT_GL_CONFIG)
for group_plan in plan.groups:
    print(f"# group {group_plan.group.number} {group_plan.group.label}: "
          f"{group_plan.selected} of {group_plan.discovered}", file=sys.stderr)
for bucket in plan.buckets:
    if bucket.gl_config != catalog.DEFAULT_GL_CONFIG:
        print(f"# {len(bucket.cases)} cases need gl config {bucket.gl_config}",
              file=sys.stderr)
    for case in bucket.cases:
        print(case)
