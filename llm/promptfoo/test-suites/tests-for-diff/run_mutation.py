#!/usr/bin/env python3
# Mutation-test grader for the tests-for-diff suite. /io contains:
#   correct.py        — the post-diff (correct) implementation
#   test_subject.py   — the model's generated test suite (imports `subject`)
#   mutants/*.py       — broken variants (each a planted regression)
# We run the generated tests against the correct code (must PASS) and against
# each mutant (must FAIL = the regression was caught). Output (stdout, one line):
#   {"correct_pass": bool, "caught": int, "total": int, "mutation_score": float}
#
# Runs in the tfd-runner container with --network none (the generated test code
# is untrusted). `subject.py` is swapped between correct/mutant for each run.
import sys
import json
import shutil
import glob
import subprocess

IO = sys.argv[1] if len(sys.argv) > 1 else '/io'


def tests_pass():
    # -x: stop at first failure (we only need to know pass vs fail).
    r = subprocess.run(
        ['python', '-m', 'pytest', '-q', '-x', '--no-header', 'test_subject.py'],
        cwd=IO, capture_output=True, text=True, timeout=90,
    )
    return r.returncode == 0


shutil.copyfile(f'{IO}/correct.py', f'{IO}/subject.py')
correct_pass = tests_pass()

mutants = sorted(glob.glob(f'{IO}/mutants/*.py'))
caught = 0
for m in mutants:
    shutil.copyfile(m, f'{IO}/subject.py')
    if not tests_pass():          # generated tests detected the regression
        caught += 1
total = len(mutants)

print(json.dumps({
    'correct_pass': correct_pass,
    'caught': caught,
    'total': total,
    'mutation_score': round(caught / total, 3) if total else 0.0,
}))
