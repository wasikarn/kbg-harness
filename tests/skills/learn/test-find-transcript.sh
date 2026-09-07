#!/usr/bin/env bash
# Unit tests for skills/meta/learn/scripts/find-transcript.sh — the transcript
# locator whose old (pre-rebuild) design picked "latest .jsonl by mtime" and
# would silently mine the wrong session's transcript whenever this repo's own
# concurrent-session pattern put more than one transcript in a project dir.
# The fix reads CLAUDE_CODE_SESSION_ID and constructs the path deterministically.
# Run standalone: bash tests/skills/learn/test-find-transcript.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/meta/learn/scripts/find-transcript.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

FAKE_HOME=$(mktemp -d)
trap 'trash "$FAKE_HOME" 2>/dev/null || true' EXIT
CWD="/fake/project"
SLUG="${CWD//\//-}"
DIR="$FAKE_HOME/.claude/projects/$SLUG"
mkdir -p "$DIR"

# --- fixture: two concurrent sessions, current one is NOT the latest by mtime ---
CURRENT_ID="11111111-1111-1111-1111-111111111111"
OTHER_ID="22222222-2222-2222-2222-222222222222"
printf 'current session content\n' > "$DIR/$CURRENT_ID.jsonl"
sleep 1.1
printf 'other, newer session content\n' > "$DIR/$OTHER_ID.jsonl"   # newer mtime than current

out=$(HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$CURRENT_ID" bash "$SCRIPT" "$CWD" 2>/dev/null)
rc=$?
picked_path=$(echo "$out" | awk '{print $1}')
if [ "$rc" -eq 0 ] && [ "$picked_path" = "$DIR/$CURRENT_ID.jsonl" ]; then
  ok "picks the current session's transcript, not the newer-mtime other session"
else
  bad "expected $DIR/$CURRENT_ID.jsonl, got '$picked_path' (rc=$rc) — old mtime-latest bug would pick $OTHER_ID.jsonl here"
fi

# --- fixture: session id set, but no matching transcript file exists ---
MISSING_ID="33333333-3333-3333-3333-333333333333"
STDOUT_LOG="$FAKE_HOME/missing-id.stdout"
STDERR_LOG="$FAKE_HOME/missing-id.stderr"
HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$MISSING_ID" bash "$SCRIPT" "$CWD" >"$STDOUT_LOG" 2>"$STDERR_LOG"
rc=$?
if [ "$rc" -ne 0 ] && [ -s "$STDERR_LOG" ]; then
  ok "fails loud (non-zero exit + stderr reason) when no transcript matches the session id"
else
  bad "expected non-zero exit + stderr on not-found, got rc=$rc stderr=$(cat "$STDERR_LOG")"
fi

# --- fixture: CLAUDE_CODE_SESSION_ID unset entirely ---
UNSET_STDERR_LOG="$FAKE_HOME/unset-id.stderr"
out=$(HOME="$FAKE_HOME" env -u CLAUDE_CODE_SESSION_ID bash "$SCRIPT" "$CWD" 2>"$UNSET_STDERR_LOG")
rc=$?
if [ "$rc" -ne 0 ] && /usr/bin/grep -qi 'CLAUDE_CODE_SESSION_ID' "$UNSET_STDERR_LOG"; then
  ok "fails loud and names the missing env var when CLAUDE_CODE_SESSION_ID is unset"
else
  bad "expected non-zero exit naming CLAUDE_CODE_SESSION_ID, got rc=$rc stderr=$(cat "$UNSET_STDERR_LOG")"
fi

# --- byte size reported matches the actual file ---
out=$(HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$CURRENT_ID" bash "$SCRIPT" "$CWD" 2>/dev/null)
reported_size=$(echo "$out" | awk '{print $2}')
actual_size=$(wc -c < "$DIR/$CURRENT_ID.jsonl" | tr -d ' ')
if [ "$reported_size" = "$actual_size" ]; then
  ok "reported byte size matches the actual transcript file"
else
  bad "expected size $actual_size, got $reported_size"
fi

echo "learn/find-transcript: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
