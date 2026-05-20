#!/usr/bin/env python3
"""
Re-emit test YAML files with clean formatting:
- Multi-line strings (containing real `\\n`): use `|` literal block to preserve breaks
- Long single-paragraph strings (>80 chars, no `\\n`): use `>` folded block for readable wrap
- Short strings: double-quoted single-line
- javascript values: preserved exactly (single line quoted, multi-line as `|`)

Round-trip safe: the script verifies that yaml.safe_load(new) == yaml.safe_load(old)
before writing.

Usage:
  ./lint-tests.py [file1 file2 ...]   # default: all *-tests.yaml in cwd
"""
import os
import sys
import glob
import yaml


def emit_literal_block(s: str, indent: int) -> str:
    """Emit string as `|` literal block — preserves all newlines exactly."""
    pad = ' ' * indent
    lines = s.split('\n')
    # If string ends with single \n, use bare `|` (clip trailing newline beyond one)
    # If ends with multiple \n, use `|+` (keep)
    # If no trailing \n, use `|-` (strip)
    if s.endswith('\n\n'):
        marker = '|+'
        # keep all
    elif s.endswith('\n'):
        marker = '|'
        # drop last empty element from split
        if lines and lines[-1] == '':
            lines = lines[:-1]
    else:
        marker = '|-'
    body = '\n'.join(pad + line if line else '' for line in lines)
    return f"{marker}\n{body}"


def emit_folded_block(s: str, indent: int) -> str:
    """Emit string as `>` folded block — wraps long prose, collapses newlines.
    Only safe when input has no internal `\\n`."""
    pad = ' ' * indent
    # Soft-wrap at ~90 chars for readability
    words = s.split()
    lines, cur = [], ''
    for w in words:
        if cur and len(cur) + 1 + len(w) > 90:
            lines.append(cur)
            cur = w
        else:
            cur = cur + ' ' + w if cur else w
    if cur:
        lines.append(cur)
    body = '\n'.join(pad + line for line in lines)
    # `>` adds a single \n at end (matches our trailing-\n input). Use `>-` if no trailing.
    marker = '>' if s.endswith('\n') else '>-'
    return f"{marker}\n{body}"


def quote_string(s: str) -> str:
    """Double-quote a short single-line string."""
    esc = s.replace('\\', '\\\\').replace('"', '\\"')
    return f'"{esc}"'


def emit_scalar(s, indent: int) -> str:
    """Choose representation for a scalar string."""
    if not isinstance(s, str):
        return str(s)
    if '\n' in s:
        return emit_literal_block(s, indent)
    if len(s) > 90:
        return emit_folded_block(s, indent)
    return quote_string(s)


def emit_test(test: dict) -> str:
    out = []
    out.append(f"- description: {quote_string(test['description'])}")

    if 'vars' in test:
        out.append("  vars:")
        for k, v in test['vars'].items():
            if isinstance(v, str):
                out.append(f"    {k}: {emit_scalar(v, 6)}")
            else:
                out.append(f"    {k}: {v}")

    if 'assert' in test:
        out.append("  assert:")
        for a in test['assert']:
            atype = a.get('type', '')
            metric = a.get('metric', '')
            value = a.get('value', '')
            out.append(f"    - type: {atype}")
            if metric:
                out.append(f"      metric: {quote_string(metric)}")
            # Only emit value if the original had one (some types like `is-json` don't)
            if 'value' in a:
                out.append(f"      value: {emit_scalar(value, 8)}")
    return '\n'.join(out)


def lint_file(path: str) -> bool:
    txt = open(path).read()
    # Preserve leading comment block
    header_lines = []
    for line in txt.split('\n'):
        if line.startswith('-'):
            break
        header_lines.append(line)
    header = '\n'.join(header_lines).rstrip()

    docs = yaml.safe_load(txt)
    if not isinstance(docs, list):
        print(f"  skip {path}: top-level is not a list")
        return False

    body = '\n\n'.join(emit_test(t) for t in docs)
    new = header + '\n\n' + body + '\n'

    # Round-trip safety check
    try:
        new_parsed = yaml.safe_load(new)
    except yaml.YAMLError as e:
        print(f"  FAIL {path}: new yaml does not parse — {e}")
        return False
    if new_parsed != docs:
        # Find first difference
        for i, (o, n) in enumerate(zip(docs, new_parsed)):
            if o != n:
                for k in set(o) | set(n):
                    if o.get(k) != n.get(k):
                        print(f"  FAIL {path}: item {i} key '{k}' differs after round-trip")
                        print(f"    orig: {repr(o.get(k))[:200]}")
                        print(f"    new:  {repr(n.get(k))[:200]}")
                        return False
        return False

    if new != txt:
        open(path, 'w').write(new)
        print(f"  ✓ {path}")
        return True
    print(f"  - {path} (no changes)")
    return False


def main():
    # Operate from the promptfoo root regardless of where we're invoked.
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    files = sys.argv[1:] or sorted(glob.glob('test-suites/*.yaml'))
    for f in files:
        lint_file(f)


if __name__ == '__main__':
    main()
