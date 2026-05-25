#!/usr/bin/env python3
# Materialize a PINNED LiveCodeBench code-generation problem set into
# problems.json so every model is benched on the identical set. Filter by
# release_version + an optional date window — contamination control: pick a
# window past the training cutoffs of the models you are comparing.
#
# Env: LCB_RELEASE (release_v1..v6), LCB_START / LCB_END (YYYY-MM-DD),
#      LCB_N (0 = all in window), LCB_OUT (path). Runs inside the LCB venv.
import os
import json

from lcb_runner.benchmarks.code_generation import load_code_generation_dataset

REL = os.environ.get("LCB_RELEASE", "release_v6")
START = os.environ.get("LCB_START") or None
END = os.environ.get("LCB_END") or None
N = int(os.environ.get("LCB_N", "0"))
OUT = os.environ.get("LCB_OUT", "/work/problems.json")

probs = load_code_generation_dataset(release_version=REL, start_date=START, end_date=END)
if N:
    probs = probs[:N]

out = [
    {
        "question_id": p.question_id,
        "question_content": p.question_content,
        "starter_code": p.starter_code,
        "contest_date": p.contest_date.isoformat(),
        "eval_sample": p.get_evaluation_sample(),
    }
    for p in probs
]
json.dump(out, open(OUT, "w"))
print(f"wrote {len(out)} problems -> {OUT} (release={REL} start={START} end={END})")
