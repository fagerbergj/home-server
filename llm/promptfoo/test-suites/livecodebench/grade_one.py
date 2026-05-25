#!/usr/bin/env python3
# Grade ONE LiveCodeBench code-generation candidate by executing it against the
# problem's hidden tests. Input: a JSON file {"eval_sample": {...}, "code": str,
# "timeout": int}. Output (stdout, last line): {"passed":0|1,"total":1,"pass1":f}.
#
# Runs inside the LCB venv (PYTHONPATH=.../LiveCodeBench). No network needed.
# LCB's executor (reliability_guard + subprocess timeouts) sandboxes the code;
# the provider additionally runs this with `docker --network none`.
import sys
import json

from lcb_runner.evaluation import codegen_metrics


def main():
    data = json.load(open(sys.argv[1]))
    metrics, *_ = codegen_metrics(
        [data["eval_sample"]],
        [[data["code"]]],
        k_list=[1],
        num_process_evaluate=1,
        timeout=int(data.get("timeout", 6)),
    )
    p1 = metrics.get("pass@1", 0.0)
    # pass@1 is a fraction (1.0) in our build; round handles a percent (100.0)
    # build too. Single problem + single generation → strictly 0 or full.
    print(json.dumps({"passed": int(round(p1) >= 1), "total": 1, "pass1": p1}))


if __name__ == "__main__":
    main()
