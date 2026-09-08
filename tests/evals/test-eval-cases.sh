#!/usr/bin/env bash
# test-eval-cases.sh: static check of evals/<case>/ for the review-agent and skill evals.
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
  case "$c" in
    tech-humanize-*) /usr/bin/grep -q 'skill: "mh:tech-humanize"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    harness-audit-*) /usr/bin/grep -q 'skill: "mh:harness-audit"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    post-mortem-*)   /usr/bin/grep -q '^/mh:post-mortem' "$d/prompt.md" || { bad "$c: prompt.md does not invoke the skill by slash command"; continue; } ;;
    compliance-audit-*) /usr/bin/grep -q '^/mh:compliance-audit' "$d/prompt.md" || { bad "$c: prompt.md does not invoke the skill by slash command"; continue; } ;;
    memory-lint-*)   /usr/bin/grep -q 'skill: "mh:memory-lint"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    learn-*)         /usr/bin/grep -q 'skill: "mh:learn"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    ideate-*)        /usr/bin/grep -q 'skill: "mh:ideate"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    deep-audit-*)    /usr/bin/grep -q 'skill: "mh:deep-audit"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    cost-report-*)   /usr/bin/grep -q 'skill: "mh:cost-report"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    ste-lint-*)      /usr/bin/grep -q 'skill: "mh:ste-lint"' "$d/prompt.md" || { bad "$c: prompt.md does not name the skill"; continue; } ;;
    *) /usr/bin/grep -q 'subagent_type: "mh:' "$d/prompt.md" || { bad "$c: prompt.md does not name a subagent_type"; continue; } ;;
  esac

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
  for f in $(/usr/bin/grep -oE '`[A-Za-z0-9_./-]+\.(py|md|ts|tsx|json)`' "$d/prompt.md" | tr -d '`' | sort -u); do
    [ -f "$ws/$f" ] || { bad "$c: scaffold did not write $f"; missing=1; }
  done
  [ "$missing" -eq 0 ] || continue

  # every grader has column-0 frontmatter with a type (the runner skips a grader
  # whose fence is indented, silently -- caught by a validator 2026-09-06), and
  # every regex grader's pattern compiles. contract.md / clean.md must also match a
  # verdict line in the shape the agent actually emits: all three live runs on
  # 2026-09-06 wrote it bold or after a `Verdict:` label, which a bare `(^|\n)\s*`
  # anchor rejects (deep-audit finding, v1.1.22).
  case "$c" in
    blind-spot-hunter-planted|silent-failure-hunter-planted) sample=$'## Verdict\n\n**1 MEDIUM, 2 LOW**' ;;
    blind-spot-hunter-clean|silent-failure-hunter-clean)     sample=$'## Verdict\n\n**CLEAN**' ;;
    test-gap-analyzer-planted)    sample=$'**Verdict:** `4 GAPS, highest 6/10`' ;;
    test-gap-analyzer-clean)      sample=$'**Verdict:** `COVERED`' ;;
    type-design-analyzer-planted) sample=$'**6 CONCERNS across 4 types, lowest Encapsulation 4/10**' ;;
    type-design-analyzer-clean)   sample=$'**SOUND**' ;;
    plan-reviewer-planted)        sample='verdict: needs-revision' ;;
    plan-reviewer-clean)          sample=$'findings: []\nverdict: production-ready' ;;
    requirement-analyst-planted)  sample='verdict: needs-clarification' ;;
    requirement-analyst-clean)    sample='verdict: ready' ;;
    tech-humanize-*)              sample='FIXTURE' ;;
    harness-audit-*)              sample=$'=== Summary ===\nCritical: 0\nWarnings: 1\nInfo:     4\n' ;;
    post-mortem-complete)         sample=$'## 1. Summary\n\n## 2. Symptom\n\n## 3. Root Cause (Mechanism)\n\n## 4. Symptom Linkage\n\n## 5. Fix\n\n## 6. Discovery Method\n\n## 7. Escape Reason\n\n## 8. Failure class\n\n## 9. Validation Proof\n\n## 10. Follow-Ups\n\n## 11. Assumption Trace' ;;
    post-mortem-missing-input)    sample='Before drafting I need the fourth input: passing validation.' ;;
    memory-lint-*)                sample='memories: 3 | links: 3 | linked: 3 | MEMORY.md: 3% of load cap | findings: 0' ;;
    learn-*)                      sample='FIXTURE' ;;
    compliance-audit-*)           sample='FIXTURE' ;;
    ideate-run)                   sample=$'- ring-buffer CAS counters [N7 V8 F9]\n★ **token lease** because...\nWhat if we took this seriously: ...' ;;
    ideate-abort)                 sample=$'```python\nwith open("notes.txt") as f:\n    for line in f:\n        ...\n```' ;;
    deep-audit-*)                 sample='**Final Verdict:** pass (7.8/10, confidence high)' ;;
    cost-report-planted)          sample=$'=== Cost summary ===\nnote: 1 of 3 rows predate dedup_usage (2026-09-04)\ntotal:     $10.0000  (3 sessions)' ;;
    cost-report-clean)            sample='Cost tracker not set up: /tmp/x/metrics/costs.jsonl not found. Enable the stop:cost-tracker hook and finish a session first.' ;;
    ste-lint-planted)             sample='notes.md line 5: rule 8.1 semicolon
notes.md line 3: rule 6.3 31 words (limit 25)
Do not skip the smoke test; a failed smoke test blocks the release.' ;;
    ste-lint-clean)               sample='status.md: no confirmed findings
The build is green. Tests pass. Deploy is ready.' ;;
    ste-lint-file-prose-only)     sample='mixed.md line 3: rule 8.1 semicolon
```bash
echo "a;b"
```' ;;
    *) sample='' ;;
  esac
  [ -n "$sample" ] || { bad "$c: no verdict sample in test-eval-cases.sh (add one to the case list)"; continue; }
  # Skill cases have no verdict token. Their proof is the fixture itself: every regex grader
  # pattern must match the scaffolded input (a not_contains tell is really planted, a contains
  # specific is really there), or the grader cannot discriminate.
  if [ "$sample" = FIXTURE ]; then
    sample=$(cat "$ws"/*.md "$ws"/*/*.md 2>/dev/null)
  fi
  # ste-lint reports rather than rewrites: a `wrong` sample proves a last_message
  # grader would reject an incorrect report, not just accept a correct one.
  wrong=''
  case "$c" in
    ste-lint-planted)         wrong='status.md: no confirmed findings, file is clean.' ;;
    ste-lint-file-prose-only) wrong='mixed.md line 6: rule 8.1 semicolon inside the code block' ;;
  esac
  if ! python3 - "$d/graders" "$sample" "$wrong" <<'PY'
import sys, os, re
bad = 0
sample = sys.argv[2]
wrong = sys.argv[3] if len(sys.argv) > 3 else ""
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
        rx = re.compile(p.group(1))
    except re.error as e:
        print(f"  bad regex in {f}: {e}"); bad = 1; continue
    fl = re.search(r"^flags: (\w+)$", m.group(1), re.M)
    flags = re.I if fl and "i" in fl.group(1) else 0
    if f in ("contract.md", "clean.md"):
        want = "match: not_contains" not in m.group(1)
        if bool(re.search(p.group(1), sample, flags)) != want:
            print(f"  {f}: pattern {'rejects' if want else 'matches'} the verdict sample {sample!r}"); bad = 1
    elif os.path.basename(os.path.dirname(sys.argv[1])).startswith(("tech-humanize-", "ste-lint-")):
        if not re.search(p.group(1), sample, flags | re.M):
            print(f"  {f}: pattern does not match the scaffolded fixture, so it cannot discriminate"); bad = 1
        if wrong and "target: last_message" in m.group(1) and re.search(p.group(1), wrong, flags | re.M):
            print(f"  {f}: pattern matches a deliberately wrong report, so it cannot discriminate"); bad = 1
sys.exit(bad)
PY
  then bad "$c: a grader is malformed"; continue; fi
  ok "$c"
done
[ "$n" -eq 44 ] || bad "expected 44 cases, found $n"

echo "eval-cases: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
