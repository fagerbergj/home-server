#!/usr/bin/env bash
# Run the same Python and Shell lint checks as .github/workflows/lint.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

mapfile -t -d '' py_files < <(git ls-files -z -- '*.py' ':!jaison/llm/vllm-patches/**' ':!torrent/search/**')
if [ "${#py_files[@]}" -gt 0 ]; then
  uvx ruff@0.17.6 check "${py_files[@]}"
  uvx mypy@2.4.1 "${py_files[@]}"
fi

mapfile -t -d '' sh_files < <(git ls-files -z -- '*.sh' ':!jaison/llm/**')
if [ "${#sh_files[@]}" -gt 0 ]; then
  shellcheck -S warning "${sh_files[@]}"
fi
