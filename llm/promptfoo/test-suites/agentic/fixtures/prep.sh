#!/usr/bin/env bash
# Regenerate the buggy-tree snapshots the seeded bugfix tasks run against.
#
# For each instance in manifest.json we archive the fix commit's PARENT — the
# state before the fix landed (and before the fix's test existed) — from a local
# document-pipeline checkout. That tree is the bug the agent must find: existing
# tests pass, so there's no signal pointing at the defect. The matching hidden
# test (the one the fix shipped) lives in hidden/<name>/ and is copied into the
# sandbox only at grade time by provider.js.
#
# Snapshots land in repos/ (gitignored). Run once before the agentic suite:
#   DP_REPO=/path/to/document-pipeline ./prep.sh   # default: ~/workspace/document-pipeline
set -euo pipefail
cd "$(dirname "$0")"   # fixtures/
DP="${DP_REPO:-$HOME/workspace/document-pipeline}"
[ -d "$DP/.git" ] || { echo "document-pipeline checkout not found at $DP (set DP_REPO)" >&2; exit 1; }

python3 - "$DP" <<'PY'
import json, os, shutil, subprocess, sys
dp = sys.argv[1]
m = json.load(open('manifest.json'))
prune = m.get('prune', [])
for inst in m['instances']:
    name, commit = inst['name'], inst['commit']
    dest = os.path.join('repos', name)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest, exist_ok=True)
    archive = subprocess.run(['git', '-C', dp, 'archive', f'{commit}^'],
                             check=True, stdout=subprocess.PIPE).stdout
    subprocess.run(['tar', '-x', '-C', dest], input=archive, check=True)
    for p in prune + inst.get('prune', []):
        target = os.path.join(dest, p)
        if not os.path.lexists(target):       # lexists: True even for dangling symlinks
            continue
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target, ignore_errors=True)
        else:
            os.remove(target)                 # plain file or (possibly dangling) symlink
    print(f'  {name}: {commit}^ -> {dest}')
print('done')
PY
