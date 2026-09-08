#!/usr/bin/env bash
# mh:ste-lint — word counter self-test, plus the target-selection and
# report-only invariants Codex flagged during plan review.
# Run standalone: bash tests/skills/test-ste-lint.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/skills/design/ste-lint/scripts/ste-lint.py"
FAIL=0

python3 "$SCRIPT" --selftest || { echo "FAIL: ste-lint.py selftest"; FAIL=1; }

TMP="$(mktemp -d)"
OUTSIDE="$TMP-outside.md"
trap 'trash "$TMP" "$OUTSIDE" 2>/dev/null || true' EXIT
(
  cd "$TMP" || exit 1
  git init -q
  git config user.email t@t.test
  git config user.name t

  # Zero changed files: a clean commit has no findings, not an error.
  printf 'hello\n' > clean.md
  git add clean.md && git commit -q -m init
  out=$(python3 "$SCRIPT" --json)
  echo "$out" | /usr/bin/grep -q '"files": \[\]' || { echo "FAIL: zero-changed-files, got: $out"; exit 1; }

  # Odd filenames: a space and a leading dash, both untracked.
  printf 'Do not use this; it is not allowed.\n' > "has space.md"
  printf 'Do not use this; it is not allowed.\n' > ./-dashfile.md
  out=$(python3 "$SCRIPT" --json)
  echo "$out" | /usr/bin/grep -q 'has space.md' || { echo "FAIL: space-filename not scanned"; exit 1; }
  echo "$out" | /usr/bin/grep -q -- '-dashfile.md' || { echo "FAIL: dash-filename not scanned"; exit 1; }

  # Symlink escaping the repo root must not be followed.
  printf 'Do not use this; it is not allowed.\n' > "$OUTSIDE"
  ln -s "$OUTSIDE" escape.md
  out=$(python3 "$SCRIPT" --json)
  echo "$out" | /usr/bin/grep -q '"path": "escape.md"' && { echo "FAIL: escaping symlink was scanned"; exit 1; }

  # Symlink staying inside the repo root must be followed like a normal file.
  printf 'Do not use this; it is not allowed.\n' > real-inside.md
  ln -s real-inside.md inside-link.md
  out=$(python3 "$SCRIPT" --json)
  echo "$out" | /usr/bin/grep -q '"path": "inside-link.md"' || { echo "FAIL: in-repo symlink was not scanned"; exit 1; }

  # Unreadable file: reported as an error (exit 2), not a crash.
  printf 'Do not use this; it is not allowed.\n' > unreadable.md
  chmod 000 unreadable.md
  python3 "$SCRIPT" unreadable.md --json > /dev/null 2>&1
  code=$?
  chmod 644 unreadable.md
  [ "$code" -eq 2 ] || { echo "FAIL: unreadable file expected exit 2, got $code"; exit 1; }

  # A semicolon inside a fenced code block is never reported; the same
  # semicolon in prose is.
  cat > mixed.md <<'EOF'
Do not use this; it is not allowed.

```
echo "a;b"
```
EOF
  out=$(python3 "$SCRIPT" mixed.md --json)
  echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
lines = [f['line'] for f in d['files'][0]['confirmed'] if f['rule'] == '8.1']
assert lines == [1], lines
" || { echo "FAIL: code-block semicolon leaked into findings"; exit 1; }

  # docs/METHODOLOGY.md is frozen: its byte cap fights Rule 4.2 directly, so a
  # default sweep must never scan it even when dirty.
  mkdir -p docs
  printf 'Do not use this; it is not allowed.\n' > docs/METHODOLOGY.md
  out=$(python3 "$SCRIPT" --json)
  echo "$out" | /usr/bin/grep -q 'METHODOLOGY.md' && { echo "FAIL: docs/METHODOLOGY.md was scanned by default sweep"; exit 1; }

  # Report-only: scanning never changes the target file's bytes.
  before=$(shasum -a 256 mixed.md)
  python3 "$SCRIPT" mixed.md > /dev/null
  after=$(shasum -a 256 mixed.md)
  [ "$before" = "$after" ] || { echo "FAIL: mixed.md mutated by a report-only run"; exit 1; }
) || FAIL=1

[ "$FAIL" -eq 0 ] && echo "PASS: test-ste-lint" || { echo "FAIL: test-ste-lint"; exit 1; }
