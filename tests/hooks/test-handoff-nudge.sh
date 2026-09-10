#!/usr/bin/env bash
# Unit tests for hooks/session/handoff-nudge.sh — the SessionStart hook that
# nudges the model to suggest /mh:handoff after a compact, once per session.
# Every non-obvious case here traces back to a specific Codex round-N finding
# from the plan review that shaped this script; see
# docs/adr/0002-mh-controlled-handoff-path.md for the full history.
# Run standalone: bash tests/hooks/test-handoff-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/handoff-nudge.sh"
. "$ROOT/tests/_lib/harness.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

FAKE_HOME=$(mktemp -d)
trap _cleanup_trash EXIT

# Every call supplies HOME (unused by the hook, but kept for parity with the
# other test suites) and a fresh TMPDIR so runs never share marker state.
run() { local body="$1" tmp="$2"; printf '%s' "$body" | HOME="$FAKE_HOME" TMPDIR="$tmp" bash "$HOOK"; }
marker_dir() { printf '%s/mh-handoff-nudge' "$1"; }

# --- first invocation for a session_id prints the nudge and claims the marker ---
T=$(fresh_tmpdir)
OUT=$(run '{"session_id":"session-one"}' "$T" 2>"$T/err")
if echo "$OUT" | grep -q '/mh:handoff now would checkpoint' && [ -d "$(marker_dir "$T")/session-one" ] && [ ! -s "$T/err" ]; then
  ok "first invocation for a session_id prints the nudge and creates its claim marker"
else
  bad "first invocation failed: out='$OUT' marker_exists=$([ -d "$(marker_dir "$T")/session-one" ] && echo yes || echo no) stderr='$(cat "$T/err")'"
fi

# --- second invocation, same session_id: silent, claim mkdir fails (already exists) ---
OUT2=$(run '{"session_id":"session-one"}' "$T" 2>"$T/err2")
if [ -z "$OUT2" ] && [ ! -s "$T/err2" ]; then
  ok "a second invocation with the same session_id is silent (already claimed)"
else
  bad "expected silence on repeat session_id, got '$OUT2' stderr='$(cat "$T/err2")'"
fi

# --- a different session_id nudges independently -- never a global-once cap ---
OUT3=$(run '{"session_id":"session-two"}' "$T" 2>"$T/err3")
if echo "$OUT3" | grep -q '/mh:handoff now would checkpoint' && [ -d "$(marker_dir "$T")/session-two" ] && [ ! -s "$T/err3" ]; then
  ok "a different session_id nudges independently, not a global-once cap"
else
  bad "expected the second session_id to nudge independently, got '$OUT3'"
fi

# --- malformed / non-JSON stdin: silent, exit 0, no crash ---
T=$(fresh_tmpdir)
OUT=$(run 'not json at all' "$T" 2>"$T/err")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$T/err" ]; then
  ok "malformed stdin JSON is silent, exit 0, no crash"
else
  bad "expected silent exit 0 on malformed JSON, got rc=$rc out='$OUT' stderr='$(cat "$T/err")'"
fi

# --- empty stdin: silent, exit 0 ---
T=$(fresh_tmpdir)
OUT=$(run '' "$T" 2>"$T/err")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$T/err" ]; then
  ok "empty stdin is silent, exit 0"
else
  bad "expected silent exit 0 on empty stdin, got rc=$rc out='$OUT'"
fi

# --- Codex round-2 review, live-reproduced: a wrong-typed session_id must not
# be stringified into a false-positive match. null/true/a number/an array/an
# object all reject; only a real, non-empty JSON string is accepted. ---
T=$(fresh_tmpdir)
ALL_SILENT=1
for payload in '{"session_id":null}' '{"session_id":true}' '{"session_id":123}' '{"session_id":[1,2]}' '{"session_id":{"a":1}}'; do
  OUT=$(run "$payload" "$T" 2>"$T/err")
  [ -z "$OUT" ] && [ ! -s "$T/err" ] || { ALL_SILENT=0; bad "wrong-typed session_id leaked output for payload $payload: '$OUT'"; }
done
if [ "$ALL_SILENT" -eq 1 ] && [ -z "$(ls -A "$(marker_dir "$T")" 2>/dev/null)" ]; then
  ok "a wrong-typed session_id (null/bool/number/array/object) is rejected, never stringified into a false match"
fi

# --- a session_id containing / or other unsafe characters is rejected before
# it ever becomes a path component ---
T=$(fresh_tmpdir)
OUT=$(run '{"session_id":"../../etc/passwd"}' "$T" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ -z "$(ls -A "$(marker_dir "$T")" 2>/dev/null)" ]; then
  ok "a session_id containing unsafe characters (path separators) is rejected before touching any path"
else
  bad "unsafe session_id was not rejected: out='$OUT'"
fi

# --- Codex round-2 review: "." and ".." both match the character class but
# must be explicitly rejected -- neither is a real session id, and ".." is a
# meaningful directory-traversal component. ---
T=$(fresh_tmpdir)
DOT_OK=1
for sid in '.' '..'; do
  OUT=$(run "{\"session_id\":\"$sid\"}" "$T" 2>"$T/err")
  [ -z "$OUT" ] && [ ! -s "$T/err" ] || { DOT_OK=0; bad "session_id '$sid' was not rejected: out='$OUT'"; }
done
if [ "$DOT_OK" -eq 1 ]; then
  ok "session_id values '.' and '..' are rejected despite matching the character class"
fi

# --- python3 unavailable: silent, exit 0. A curated PATH keeps every other
# needed binary (bash itself, mkdir, stat, id) real, only python3 absent --
# emptying PATH entirely would also remove bash and produce a false failure
# unrelated to this guard. ---
T=$(fresh_tmpdir)
NOPY_DIR=$(mktemp -d); EXTRA_TRASH+=("$NOPY_DIR")
for bin in bash mkdir stat id sh; do
  real=$(command -v "$bin" 2>/dev/null) || continue
  ln -sf "$real" "$NOPY_DIR/$bin"
done
OUT=$(printf '{"session_id":"session-one"}' | HOME="$FAKE_HOME" TMPDIR="$T" PATH="$NOPY_DIR" bash "$HOOK" 2>"$T/err")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$T/err" ]; then
  ok "python3 unavailable (curated PATH) is silent, exit 0"
else
  bad "expected silent exit 0 with python3 unavailable, got rc=$rc out='$OUT' stderr='$(cat "$T/err")'"
fi

# --- the base directory pre-planted as a symlink to a real, same-owner
# directory is rejected -- no marker ever created inside the symlink's
# target. Tested against the base path in its real (no-trailing-slash) form,
# since a trailing-slash form is exactly what let this slip past review. ---
T=$(fresh_tmpdir)
REAL_TARGET="$T-target"; mkdir -p "$REAL_TARGET"; EXTRA_TRASH+=("$REAL_TARGET")
ln -s "$REAL_TARGET" "$(marker_dir "$T")"
OUT=$(run '{"session_id":"session-one"}' "$T" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ -z "$(ls -A "$REAL_TARGET" 2>/dev/null)" ]; then
  ok "a base directory pre-planted as a symlink is rejected, nothing created in its target"
else
  bad "symlinked base directory was followed: out='$OUT' target_contents='$(ls -A "$REAL_TARGET" 2>/dev/null)'"
fi

# --- the base directory pre-existing with a foreign owner is rejected, never
# used -- a normal test process can't actually chown to another real user, so
# a PATH-shimmed `stat` simulates a foreign owner UID deterministically. ---
T=$(fresh_tmpdir)
mkdir -p "$(marker_dir "$T")"
STATSHIM_DIR=$(mktemp -d); EXTRA_TRASH+=("$STATSHIM_DIR")
cat > "$STATSHIM_DIR/stat" <<'SHIMEOF'
#!/usr/bin/env bash
# Always report an owner UID that can never equal the real caller's `id -u`.
printf '999999\n'
SHIMEOF
chmod +x "$STATSHIM_DIR/stat"
OUT=$(printf '{"session_id":"session-one"}' | HOME="$FAKE_HOME" TMPDIR="$T" PATH="$STATSHIM_DIR:$PATH" bash "$HOOK" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ ! -d "$(marker_dir "$T")/session-one" ]; then
  ok "a base directory owned by a different (simulated) user is rejected, never used"
else
  bad "foreign-owned base directory was used: out='$OUT'"
fi

# --- the marker lands under a $TMPDIR-derived path, never under
# $HOME/.claude/state/ (that prefix is reserved for per-project state
# elsewhere in this repo) ---
T=$(fresh_tmpdir)
run '{"session_id":"session-one"}' "$T" >/dev/null 2>"$T/err"
if [ -d "$(marker_dir "$T")/session-one" ] && [ ! -e "$FAKE_HOME/.claude/state/mh-handoff-nudge" ] && [ ! -s "$T/err" ]; then
  ok "the marker lands under \$TMPDIR, never under \$HOME/.claude/state/"
else
  bad "expected the marker only under \$TMPDIR, stderr empty: stderr='$(cat "$T/err")'"
fi

# --- a mkdir failure on the claim itself (base directory read-only) is
# silent, no nudge printed -- proving the print is gated on claim success,
# not a separate step that can drift from it ---
T=$(fresh_tmpdir)
mkdir -p "$(marker_dir "$T")"
chmod 500 "$(marker_dir "$T")"
OUT=$(run '{"session_id":"session-one"}' "$T" 2>"$T/err")
RESULT_OK=0
[ -z "$OUT" ] && [ ! -s "$T/err" ] && RESULT_OK=1
chmod 700 "$(marker_dir "$T")"
if [ "$RESULT_OK" -eq 1 ]; then
  ok "a claim-mkdir failure (read-only base) is silent, no nudge printed"
else
  bad "expected silence when the claim mkdir fails: out='$OUT'"
fi

# --- compliance-audit finding: a session_id ending in a newline must be
# rejected outright, not silently truncated into a shorter "valid-looking"
# marker. The character-class check now runs in python3 against the
# untruncated string, before bash's $(...) strips the trailing newline --
# reverting that fix reproduces a marker named "foo" for input "foo\n". ---
T=$(fresh_tmpdir)
OUT=$(printf '{"session_id":"foo\\n"}' | HOME="$FAKE_HOME" TMPDIR="$T" bash "$HOOK" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ -z "$(ls -A "$(marker_dir "$T")" 2>/dev/null)" ]; then
  ok "a session_id with a trailing newline is rejected, not truncated into a mangled marker"
else
  bad "trailing-newline session_id was not rejected: out='$OUT' marker_dir='$(ls -A "$(marker_dir "$T")" 2>/dev/null)'"
fi

# --- compliance-audit finding: a session_id containing an embedded NUL byte
# must be rejected, and rejected silently -- bash's own command substitution
# drops NUL bytes and prints "warning: command substitution: ignored null
# byte in input" to stderr, which the same python3-side fix above prevents by
# never letting a NUL-containing value leave python3 in the first place. ---
T=$(fresh_tmpdir)
OUT=$(printf '{"session_id":"foo\\u0000bar"}' | HOME="$FAKE_HOME" TMPDIR="$T" bash "$HOOK" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ -z "$(ls -A "$(marker_dir "$T")" 2>/dev/null)" ]; then
  ok "a session_id with an embedded NUL byte is rejected, stderr stays empty"
else
  bad "NUL-byte session_id was not cleanly rejected: out='$OUT' stderr='$(cat "$T/err")'"
fi

# --- compliance-audit finding: an id -u failure must not leak to stderr --
# the ownership check redirects it explicitly now. A PATH-shimmed id command
# always fails; every other needed binary stays real. ---
T=$(fresh_tmpdir)
IDFAIL_DIR=$(mktemp -d); EXTRA_TRASH+=("$IDFAIL_DIR")
for bin in bash mkdir stat sh python3 dirname; do
  real=$(command -v "$bin" 2>/dev/null) || continue
  ln -sf "$real" "$IDFAIL_DIR/$bin"
done
cat > "$IDFAIL_DIR/id" <<'SHIMEOF'
#!/bin/sh
echo "id: shim failure" >&2
exit 1
SHIMEOF
chmod +x "$IDFAIL_DIR/id"
OUT=$(printf '{"session_id":"session-one"}' | HOME="$FAKE_HOME" TMPDIR="$T" PATH="$IDFAIL_DIR" bash "$HOOK" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ]; then
  ok "an id -u failure is silent, no nudge, no stderr leak"
else
  bad "id -u failure leaked: out='$OUT' stderr='$(cat "$T/err")'"
fi

# --- compliance-audit finding (TOCTOU): the base directory could be swapped
# for a symlink between the pre-claim ownership check and the claim mkdir.
# A PATH-shimmed id command -- the last real command the script runs before
# the claim mkdir -- performs the swap as its own side effect, simulating a
# racing local process; /bin/rm and /bin/ln are used by absolute path inside
# the shim so the swap doesn't depend on the shimmed (deliberately narrow)
# PATH. The post-claim recheck must detect the swap, roll the claim back,
# and print nothing. ---
T=$(fresh_tmpdir)
REAL_TARGET="$T-race-target"; mkdir -p "$REAL_TARGET"; EXTRA_TRASH+=("$REAL_TARGET")
mkdir -p "$(marker_dir "$T")"
RACE_DIR=$(mktemp -d); EXTRA_TRASH+=("$RACE_DIR")
for bin in bash mkdir stat sh python3 rmdir dirname; do
  real=$(command -v "$bin" 2>/dev/null) || continue
  ln -sf "$real" "$RACE_DIR/$bin"
done
cat > "$RACE_DIR/id" <<SHIMEOF
#!/bin/sh
/bin/rm -rf "$(marker_dir "$T")"
/bin/ln -s "$REAL_TARGET" "$(marker_dir "$T")"
exec /usr/bin/id "\$@"
SHIMEOF
chmod +x "$RACE_DIR/id"
OUT=$(printf '{"session_id":"race-probe"}' | HOME="$FAKE_HOME" TMPDIR="$T" PATH="$RACE_DIR" bash "$HOOK" 2>"$T/err")
if [ -z "$OUT" ] && [ ! -s "$T/err" ] && [ ! -e "$REAL_TARGET/race-probe" ]; then
  ok "a base directory swapped for a symlink between the check and the claim is caught and rolled back"
else
  bad "TOCTOU swap was not caught: out='$OUT' target_has_marker=$([ -e "$REAL_TARGET/race-probe" ] && echo yes || echo no)"
fi

# --- the registered hooks.json entry's matcher is exactly "compact" -- a
# config property, not something the script itself can be driven to prove,
# since the script never reads the SessionStart "source" field at all (same
# reasoning as tests/hooks/test-handoff-surface.sh's matcher assertion) ---
MATCHER=$(python3 -c "
import json
with open('$ROOT/hooks/hooks.json') as f:
    data = json.load(f)
for entry in data['hooks'].get('SessionStart', []):
    cmd = entry.get('hooks', [{}])[0].get('command', '')
    if cmd.endswith('handoff-nudge.sh\"'):
        print(entry.get('matcher', ''))
        break
")
if [ "$MATCHER" = "compact" ]; then
  ok "hooks.json matcher for session:handoff-nudge is exactly 'compact'"
else
  bad "expected matcher 'compact', got '$MATCHER'"
fi

echo "hooks/handoff-nudge: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
