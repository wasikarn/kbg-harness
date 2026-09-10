#!/usr/bin/env bash
# Unit tests for hooks/sensors/fragments-capture.sh — the PostToolUse
# (Write|Edit) hook that records a durable pointer when an armed session's
# write plausibly targets a writing-fragments document. Every non-obvious
# case here traces back to a specific Codex round-N finding; see
# docs/adr/0003-writing-fragments-pointer-capture.md for the full history.
# Run standalone: bash tests/hooks/test-fragments-capture.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/sensors/fragments-capture.sh"
ARM_HOOK="$ROOT/hooks/sensors/fragments-arm.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

FAKE_HOME=$(mktemp -d)
EXTRA_TRASH=()
_cleanup_trash() {
  local t targets=()
  [ -n "${FAKE_HOME:-}" ] && targets+=("$FAKE_HOME")
  for t in "${EXTRA_TRASH[@]:-}"; do
    [ -n "$t" ] && targets+=("$t")
  done
  [ "${#targets[@]}" -eq 0 ] || trash "${targets[@]}" 2>/dev/null
  return 0
}
trap _cleanup_trash EXIT

fresh_tmpdir() { local d; d=$(mktemp -d); [ -n "$d" ] && EXTRA_TRASH+=("$d"); printf '%s' "$d"; }
fresh_repo() {
  local d; d=$(fresh_tmpdir)
  (cd "$d" && git init -q && git config user.email t@t.com && git config user.name t) >/dev/null 2>&1
  printf '%s' "$d"
}
docs_dir_for() {
  local root="$1" sh
  sh=$(bash -c ". '$ROOT/scripts/_lib/slug-hash.sh'; slug_hash '$root'")
  printf '%s/.claude/state/mh-fragments/%s/documents' "$FAKE_HOME" "$sh"
}
arm() { # arm <session_id> <tmpdir> <repo> [prompt-suffix]
  local sid="$1" t="$2" repo="$3" suffix="${4:-}"
  printf '{"session_id":"%s","cwd":"%s","prompt":"/writing-fragments %s"}' "$sid" "$repo" "$suffix" \
    | HOME="$FAKE_HOME" TMPDIR="$t" bash "$ARM_HOOK" >/dev/null 2>/dev/null
}
capture() { # capture <session_id> <tmpdir> <repo> <tool_name> <file_path> <content-or-empty>
  local sid="$1" t="$2" repo="$3" tool="$4" fp="$5" content="${6:-}"
  if [ "$tool" = "Write" ]; then
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$sid" "$repo" "$fp" "$content" \
      | HOME="$FAKE_HOME" TMPDIR="$t" bash "$HOOK"
  else
    printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$sid" "$repo" "$fp" \
      | HOME="$FAKE_HOME" TMPDIR="$t" bash "$HOOK"
  fi
}

# --- unarmed session: readdir gate keeps this silent and non-capturing ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
printf '# T\nfrag\n' > "$REPO/x.md"
OUT=$(capture "unarmed" "$T" "$REPO" Write "$REPO/x.md" '# T\\nfrag\\n' 2>"$T/err")
DOCS=$(docs_dir_for "$REPO")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ -z "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "an unarmed session's write is silent, nothing captured"
else
  bad "unarmed write should not capture: out='$OUT' json='$(find "$DOCS" -name '*.json' 2>/dev/null)'"
fi

# --- candidate present, exact canonical match -> captured, marker cleaned up ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c1" "$T" "$REPO" "$REPO/frags.md"
printf '# Title\nfrag one\n' > "$REPO/frags.md"
capture "c1" "$T" "$REPO" Write "$REPO/frags.md" '# Title\\nfrag one\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
REC=$(find "$DOCS" -name '*.json' 2>/dev/null | head -n1)
MARKERS_LEFT=$(find "$T/mh-fragments-arm" -maxdepth 1 -name 'c1.*' ! -name 'c1.current' 2>/dev/null)
if [ -n "$REC" ] && [ ! -s "$T/err" ] && [ -z "$MARKERS_LEFT" ]; then
  ok "candidate present + exact match: captured, marker fully cleaned up"
else
  bad "expected a capture with cleanup: rec='$REC' leftover='$MARKERS_LEFT' err='$(cat "$T/err")'"
fi

# --- candidate present, a DIFFERENT file written -> no heuristic fallback,
# never captured, marker stays armed ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c2" "$T" "$REPO" "$REPO/frags.md"
printf '# Unrelated\nfrag\n' > "$REPO/README.md"
capture "c2" "$T" "$REPO" Write "$REPO/README.md" '# Unrelated\\nfrag\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
MARKER=$(find "$T/mh-fragments-arm" -maxdepth 1 -type d -name 'c2.*' 2>/dev/null)
# NOTE: $DOCS existing as a directory is NOT itself proof of a capture --
# fragments-arm.sh's own best-effort known-path lookup calls
# fragments_docs_dir too, which creates the (empty) documents/ dir as a
# side effect of just checking for an existing record. The only real proof
# of a capture is a *.json file inside it.
if [ -z "$(find "$DOCS" -name '*.json' 2>/dev/null)" ] && [ -n "$MARKER" ] && [ ! -s "$T/err" ]; then
  ok "candidate present + unrelated write: no heuristic fallback, not captured, still armed"
else
  bad "expected no capture with candidate mismatch: json='$(find "$DOCS" -name '*.json' 2>/dev/null)' marker='$MARKER'"
fi
# the real candidate path still captures afterward
printf '# Title\nfrag\n' > "$REPO/frags.md"
capture "c2" "$T" "$REPO" Write "$REPO/frags.md" '# Title\\nfrag\\n' >/dev/null 2>/dev/null
DOCS=$(docs_dir_for "$REPO")
if [ -d "$DOCS" ] && [ -n "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "a later write to the actual candidate path still captures"
else
  bad "the real candidate write should still have captured after the mismatch"
fi

# --- no candidate, heuristic tier: Write with H1 to a .md file captures ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c3" "$T" "$REPO"
printf '# Heuristic\nfrag\n' > "$REPO/notes.md"
capture "c3" "$T" "$REPO" Write "$REPO/notes.md" '# Heuristic\\nfrag\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
if [ -d "$DOCS" ] && [ -n "$(find "$DOCS" -name '*.json' 2>/dev/null)" ] && [ ! -s "$T/err" ]; then
  ok "no candidate, Write with H1 to .md: heuristic tier captures"
else
  bad "expected heuristic capture: docs_exists=$([ -d "$DOCS" ] && echo yes || echo no)"
fi

# --- no candidate, Edit to any .md file captures too -- an accepted,
# explicitly-named false-positive risk of the heuristic tier ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c4" "$T" "$REPO"
printf 'no h1 here\n' > "$REPO/README.md"
capture "c4" "$T" "$REPO" Edit "$REPO/README.md" >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
if [ -d "$DOCS" ] && [ -n "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "no candidate, Edit to unrelated .md: heuristic tier captures (accepted gap)"
else
  bad "expected the accepted-gap heuristic capture on an Edit .md"
fi

# --- no candidate, Write WITHOUT an H1 to a .md file does not capture ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c5" "$T" "$REPO"
printf 'no h1\n' > "$REPO/notes.md"
capture "c5" "$T" "$REPO" Write "$REPO/notes.md" 'no h1\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
if [ ! -d "$DOCS" ] || [ -z "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "no candidate, Write without an H1: not captured"
else
  bad "a Write without an H1 should not pass the heuristic tier"
fi

# --- non-.md write never captures regardless of candidate ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c6" "$T" "$REPO"
printf 'const x = 1;\n' > "$REPO/index.js"
capture "c6" "$T" "$REPO" Write "$REPO/index.js" 'const x = 1;\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
if [ ! -d "$DOCS" ] || [ -z "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "a non-.md write never captures"
else
  bad "a .js write should never be captured by the heuristic"
fi

# --- round-4 regression: arm A, then arm B (re-invoke), claim B via a
# capture -- a LATER write must never fall back to capturing against A,
# since the pointer only ever names one generation at a time ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c7" "$T" "$REPO" "$REPO/a.md"
arm "c7" "$T" "$REPO" "$REPO/b.md"
printf '# B\nfrag\n' > "$REPO/b.md"
capture "c7" "$T" "$REPO" Write "$REPO/b.md" '# B\\nfrag\\n' >/dev/null 2>/dev/null
DOCS=$(docs_dir_for "$REPO")
COUNT_AFTER_B=$(find "$DOCS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
printf '# A\nfrag\n' > "$REPO/a.md"
capture "c7" "$T" "$REPO" Write "$REPO/a.md" '# A\\nfrag\\n' >/dev/null 2>"$T/err"
COUNT_AFTER_A_ATTEMPT=$(find "$DOCS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT_AFTER_B" -eq 1 ] && [ "$COUNT_AFTER_A_ATTEMPT" -eq 1 ] && [ ! -s "$T/err" ]; then
  ok "round-4 regression: arm A -> arm B -> claim B -> write A does not capture against the superseded A"
else
  bad "stale generation A was reselected: after_b=$COUNT_AFTER_B after_a_attempt=$COUNT_AFTER_A_ATTEMPT"
fi

# --- an expired marker (older than the arm window) is swept and never
# captures ---
T=$(fresh_tmpdir)
REPO=$(fresh_repo)
arm "c8" "$T" "$REPO" "$REPO/frags.md"
MARKER=$(find "$T/mh-fragments-arm" -maxdepth 1 -type d -name 'c8.*' 2>/dev/null | head -n1)
OLD_TS=$(( $(date +%s) - 3600 ))
touch -t "$(date -r "$OLD_TS" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$OLD_TS" +%Y%m%d%H%M.%S)" "$MARKER" 2>/dev/null
printf '# Title\nfrag\n' > "$REPO/frags.md"
capture "c8" "$T" "$REPO" Write "$REPO/frags.md" '# Title\\nfrag\\n' >/dev/null 2>"$T/err"
DOCS=$(docs_dir_for "$REPO")
if [ ! -d "$DOCS" ] || [ -z "$(find "$DOCS" -name '*.json' 2>/dev/null)" ]; then
  ok "an expired marker (past the arm window) is swept, never captures"
else
  bad "an expired marker should never capture: docs='$(find "$DOCS" -name '*.json' 2>/dev/null)'"
fi

echo "hooks/fragments-capture: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
