#!/usr/bin/env bash
# large-code-runner.sh — receives a write_file(path, content) tool call as JSON
# on stdin, writes the content to <tmp_dir>/solution.py, runs compile check +
# pytest. Emits {"compile": bool, "passed": N, "total": M, "reason": "..."}.
#
# Usage:
#   echo "<json tool_call args>" | ./large-code-runner.sh <test_name> <tmp_dir>
#
# The grader extracts content from the tool call and pipes raw text — we no
# longer parse markdown fences or model prose.

set -euo pipefail

# Use a dedicated venv if one exists (avoids PEP 668 issues on modern Debian/Ubuntu).
# Set up once with:
#   python3 -m venv ~/.venvs/eval && \
#   ~/.venvs/eval/bin/pip install pytest aiohttp pygame
VENV_PY="${EVAL_VENV_PYTHON:-$HOME/.venvs/eval/bin/python3}"
if [[ -x "$VENV_PY" ]]; then
  PYTHON="$VENV_PY"
else
  PYTHON="python3"
fi

TEST_NAME="${1:?test name required}"
TMP_DIR="${2:?tmp dir required}"
TEST_DIR="$(dirname "$(realpath "$0")")/../large-code/${TEST_NAME}"

if [[ ! -d "$TEST_DIR" ]]; then
  echo '{"compile": false, "passed": 0, "total": 0, "reason": "test dir not found"}'
  exit 0
fi

mkdir -p "$TMP_DIR"

# stdin is the raw file content (already extracted from the tool call by the
# grader). Write it verbatim — no markdown parsing.
cat > "$TMP_DIR/solution.py"
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
  reason="$(echo "$PYTEST_OUT" | tail -c 400 | python3 -c "import sys,json;print(json.dumps('pytest collected no tests — output: '+sys.stdin.read()))")"
  echo "{\"compile\": true, \"passed\": 0, \"total\": 0, \"reason\": $reason}"
  exit 0
fi

echo "{\"compile\": true, \"passed\": $PASSED, \"total\": $TOTAL, \"reason\": \"$PASSED/$TOTAL pytest passed\"}"
