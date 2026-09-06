#!/usr/bin/env bash
# test-eval-cases.sh: static check of evals/<case>/ for the review-agent evals.
# `claude plugin eval` is early-access gated, so this keeps the suite loadable
# without running it: every case has prompt.md + case.yaml + >=3 graders, the
# scaffold_script runs in a temp dir and writes the files the prompt names, and
# every regex grader's pattern compiles (Python re, same dialect family).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
EVALS="$HERE/../../evals"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'trash "$TMP" 2>/dev/null || true' EXIT

n=0
for d in "$EVALS"/*/; do
  c=$(basename "$d"); n=$((n + 1))
  [ -f "$d/prompt.md" ] && [ -f "$d/case.yaml" ] || { bad "$c: prompt.md or case.yaml missing"; continue; }
  g=$(ls "$d/graders"/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$g" -ge 3 ] || { bad "$c: $g graders (need >=3)"; continue; }
  /usr/bin/grep -q '^schema_version: "1.1"' "$d/case.yaml" || { bad "$c: case.yaml lacks schema_version 1.1"; continue; }
  /usr/bin/grep -q 'subagent_type: "mh:' "$d/prompt.md" || { bad "$c: prompt.md does not name a subagent_type"; continue; }

  # scaffold_script: extract the block, run it in a temp workspace, check every file prompt.md names.
  ws="$TMP/$c"; mkdir -p "$ws"
  python3 - "$d/case.yaml" > "$ws/scaffold.sh" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
out, on = [], False
for l in lines:
    if on:
        if l.strip() and not l.startswith("    "):
            break
        out.append(l[4:])
    elif l.strip() == "scaffold_script: |":
        on = True
sys.stdout.write("\n".join(out) + "\n")
PY
  [ -s "$ws/scaffold.sh" ] || { bad "$c: scaffold_script empty"; continue; }
  if ! (cd "$ws" && bash scaffold.sh >/dev/null 2>&1); then bad "$c: scaffold_script failed"; continue; fi
  missing=0
  for f in $(/usr/bin/grep -oE '`[A-Za-z0-9_./-]+\.(py|md|tsx|json)`' "$d/prompt.md" | tr -d '`' | sort -u); do
    [ -f "$ws/$f" ] || { bad "$c: scaffold did not write $f"; missing=1; }
  done
  [ "$missing" -eq 0 ] || continue

  # every grader has column-0 frontmatter with a type (the runner skips a grader
  # whose fence is indented, silently -- caught by a validator 2026-09-06), and
  # every regex grader's pattern compiles.
  if ! python3 - "$d/graders" <<'PY'
import sys, os, re
bad = 0
for f in sorted(os.listdir(sys.argv[1])):
    s = open(os.path.join(sys.argv[1], f)).read()
    m = re.match(r"---\n([\s\S]*?)\n---\n", s)
    if not m or not re.search(r"^type: (regex|tool_used|tool_order|file_exists|llm|baseline)$", m.group(1), re.M):
        print(f"  {f}: no column-0 frontmatter with a known type"); bad = 1; continue
    if "type: regex" not in m.group(1):
        continue
    p = re.search(r"^pattern: '(.*)'$", m.group(1), re.M)
    if not p:
        print(f"  no pattern in {f}"); bad = 1; continue
    try:
        re.compile(p.group(1))
    except re.error as e:
        print(f"  bad regex in {f}: {e}"); bad = 1
sys.exit(bad)
PY
  then bad "$c: a grader is malformed"; continue; fi
  ok "$c"
done
[ "$n" -eq 10 ] || bad "expected 10 cases, found $n"

echo "eval-cases: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
