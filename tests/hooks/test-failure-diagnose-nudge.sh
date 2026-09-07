#!/usr/bin/env bash
# Unit tests for hooks/sensors/failure-diagnose-nudge.{sh,py} (GH #153).
# Advisory PostToolUse(Bash) sensor: never blocks (always exit 0), emits a
# diagnose-before-retry nudge on non-zero exit, capped at 3 per distinct
# command per session.
# Run standalone: bash tests/hooks/test-failure-diagnose-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SENSOR="$ROOT/hooks/sensors/failure-diagnose-nudge.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# Build a PostToolUse(Bash) payload. Uses json.dumps so command text with
# quotes/backslashes doesn't produce malformed JSON (same rationale as
# tests/hooks/test-gates.sh's bash_payload).
posttooluse_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "tool_response": {"exit_code": int(sys.argv[2])}}))' "$1" "$2"
}

STATE_DIR=$(mktemp -d)
trap '[ -n "$STATE_DIR" ] && trash "$STATE_DIR" 2>/dev/null || true' EXIT
STATE="$STATE_DIR/state.json"

# --- success (exit 0) never nudges ---
out=$(posttooluse_payload "ls -la" 0 | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "exit 0 -- no nudge, exit 0"
else
  bad "exit 0 should produce no output and exit 0, got rc=$rc out='$out'"
fi

# --- failure (exit 1) nudges once ---
out=$(posttooluse_payload "make build" 1 | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "exit 1 -- nudge emitted, exit 0 (never blocks)"
else
  bad "exit 1 should emit the nudge and exit 0, got rc=$rc out='$out'"
fi

# --- cap enforcement: same command failing repeatedly stops nudging after CAP=3 ---
trash "$STATE" 2>/dev/null || true
nudge_count=0
for _ in 1 2 3 4 5; do
  out=$(posttooluse_payload "flaky-cmd --retry" 1 | bash "$SENSOR" "$STATE")
  echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge' && nudge_count=$((nudge_count + 1))
done
if [ "$nudge_count" -eq 3 ]; then
  ok "cap enforcement: exactly 3 nudges across 5 identical failures (was uncapped in the trialed plugin)"
else
  bad "expected exactly 3 nudges across 5 identical failures, got $nudge_count"
fi

# --- a DIFFERENT failing command gets its own fresh cap ---
out=$(posttooluse_payload "a-completely-different-command" 1 | bash "$SENSOR" "$STATE")
if echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "a different failing command is not affected by another command's exhausted cap"
else
  bad "a fresh distinct command should still nudge even after a different command's cap is exhausted"
fi

# --- unparseable stdin: fail-open, no crash, no nudge ---
out=$(printf 'not json at all' | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "unparseable payload -- fails open silently, exit 0"
else
  bad "unparseable payload should fail open with no output, got rc=$rc out='$out'"
fi

# --- missing python3: fail-open with a stderr announcement (GH #93 posture) ---
# Payload written to a file and redirected (not piped from a live process):
# the sensor's python3-missing fast path never reads stdin at all, so a live
# upstream writer piping into it can hit a benign SIGPIPE race that pollutes
# the captured exit status -- redirecting from a file sidesteps that.
# /bin has bash but no python3 on macOS (Apple's python3 stub lives in
# /usr/bin) -- a plain, static PATH value, no computed executable path.
STDERR_CAP="$STATE_DIR/stderr.txt"
posttooluse_payload "make build" 1 > "$STATE_DIR/payload.json"
out=$(PATH=/bin bash "$SENSOR" "$STATE" < "$STATE_DIR/payload.json" 2>"$STDERR_CAP")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && /usr/bin/grep -qi 'python3 not found' "$STDERR_CAP"; then
  ok "missing python3 -- fails open AND announces on stderr (GH #93 posture)"
else
  bad "missing python3 should fail open + announce, got rc=$rc out='$out' stderr='$(cat "$STDERR_CAP" 2>/dev/null)'"
fi

# --- default_state_path keys off the payload's own session_id, not just the
# env var -- a missing CLAUDE_CODE_SESSION_ID must not collapse every session
# onto one shared, never-reset counter file ---
FAKE_TMPDIR="$STATE_DIR/tmp-default"
mkdir -p "$FAKE_TMPDIR"
payload=$(posttooluse_payload "default-path-cmd" 1)
payload=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["session_id"]="sess-xyz"; print(json.dumps(d))' "$payload")
out=$(
  unset CLAUDE_CODE_SESSION_ID
  export TMPDIR="$FAKE_TMPDIR"
  echo "$payload" | bash "$SENSOR"
)
rc=$?
expected_state="$FAKE_TMPDIR/mh-sensors/failure-nudge-sess-xyz.json"
if [ "$rc" -eq 0 ] && [ -f "$expected_state" ] && echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "default_state_path uses the payload's session_id, staying session-scoped without the env var"
else
  bad "expected state file at $expected_state, got rc=$rc out='$out'"
fi

echo "failure-diagnose-nudge: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
