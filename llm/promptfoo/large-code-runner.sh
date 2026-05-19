#!/usr/bin/env bash
# large-code-runner.sh — extracts Python code from stdin (model output),
# writes to a tmpdir, runs compile check + pytest, emits JSON result.
#
# Usage:
#   echo "<model output>" | ./large-code-runner.sh <test_name> <tmp_dir>
#
# Outputs JSON: {"compile": bool, "passed": N, "total": M, "reason": "..."}

set -euo pipefail

# Use a dedicated venv if one exists (avoids PEP 668 issues on modern Debian/Ubuntu).
# Set up once with: python3 -m venv ~/.venvs/eval && ~/.venvs/eval/bin/pip install pytest aiohttp
VENV_PY="${EVAL_VENV_PYTHON:-$HOME/.venvs/eval/bin/python3}"
if [[ -x "$VENV_PY" ]]; then
  PYTHON="$VENV_PY"
else
  PYTHON="python3"
fi

TEST_NAME="${1:?test name required}"
TMP_DIR="${2:?tmp dir required}"
TEST_DIR="$(dirname "$(realpath "$0")")/large-code-tests/${TEST_NAME}"

if [[ ! -d "$TEST_DIR" ]]; then
  echo '{"compile": false, "passed": 0, "total": 0, "reason": "test dir not found"}'
  exit 0
fi

# Read model output from stdin, extract all ```python ... ``` blocks (or fall
# back to the whole output). The output is passed via an env var with a
# *quoted* heredoc delimiter so bash performs no interpolation — earlier
# versions used `o = """$OUTPUT"""` which broke whenever the model emitted
# Python docstrings (`"""..."""`) since the closing quotes terminated the
# string early and the remainder leaked back to bash/python.
OUTPUT="$(cat)"
CODE="$(OUTPUT="$OUTPUT" python3 - <<'PYEOF'
import os, re
o = os.environ['OUTPUT']
blocks = re.findall(r'```(?:python|py)?\s*\n(.*?)\n```', o, re.DOTALL)
print('\n\n'.join(blocks) if blocks else o)
PYEOF
)"

mkdir -p "$TMP_DIR"
echo "$CODE" > "$TMP_DIR/solution.py"
cp "$TEST_DIR/test_solution.py" "$TMP_DIR/test_solution.py"

cd "$TMP_DIR"

# Compile check: try to import the module
if ! "$PYTHON" -c "import solution" 2>/tmp/compile.err; then
  err="$(head -c 300 /tmp/compile.err | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")"
  echo "{\"compile\": false, \"passed\": 0, \"total\": 0, \"reason\": $err}"
  exit 0
fi

# Run pytest with JSON-ish output we can parse from exit code + stdout
PYTEST_OUT="$("$PYTHON" -m pytest test_solution.py --tb=no -q 2>&1 || true)"
PASSED=$(echo "$PYTEST_OUT" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+' || echo 0)
FAILED=$(echo "$PYTEST_OUT" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+' || echo 0)
ERRORED=$(echo "$PYTEST_OUT" | grep -oE '[0-9]+ error' | head -1 | grep -oE '[0-9]+' || echo 0)
TOTAL=$((PASSED + FAILED + ERRORED))

if [[ "$TOTAL" -eq 0 ]]; then
  echo "{\"compile\": true, \"passed\": 0, \"total\": 0, \"reason\": \"pytest collected no tests\"}"
  exit 0
fi

echo "{\"compile\": true, \"passed\": $PASSED, \"total\": $TOTAL, \"reason\": \"$PASSED/$TOTAL pytest passed\"}"
