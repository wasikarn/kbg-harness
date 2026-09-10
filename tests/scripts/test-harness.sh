#!/usr/bin/env bash
# test-harness.sh — unit tests for tests/_lib/harness.sh, the shared
# fresh_tmpdir/fresh_repo/track_trash/_cleanup_trash trio 5 test files
# migrated to in v1.1.68. Direct, isolated coverage of the empty-string
# filter specifically: this is the exact bug class that moved this repo's
# working tree to Trash mid-session (`trash ""` deletes the cwd) --
# test-gap-analyzer finding, confirmed real: every existing call site
# passes a real path, so nothing exercises the filter itself in isolation.
# Run standalone: bash tests/scripts/test-harness.sh
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
LIB="$ROOT/tests/_lib/harness.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== tests/_lib/harness.sh ==="

[ -f "$LIB" ] && ok "tests/_lib/harness.sh exists" || bad "tests/_lib/harness.sh missing"

# track_trash "" must never append to EXTRA_TRASH.
COUNT=$(bash -c ". '$LIB'; track_trash \"\"; echo \"\${#EXTRA_TRASH[@]}\"")
if [ "$COUNT" = "0" ]; then
  ok "track_trash '' does not add an empty string to EXTRA_TRASH"
else
  bad "track_trash '' should leave EXTRA_TRASH empty, got count=$COUNT"
fi

# track_trash with a real path DOES append it (the trio isn't just silent).
COUNT2=$(bash -c ". '$LIB'; track_trash \"/tmp/some-real-path\"; echo \"\${#EXTRA_TRASH[@]}\"")
if [ "$COUNT2" = "1" ]; then
  ok "track_trash <real-path> adds exactly one entry to EXTRA_TRASH"
else
  bad "track_trash <real-path> expected count=1, got $COUNT2"
fi

# _cleanup_trash with EXTRA_TRASH full of empties and an empty FAKE_HOME
# must never invoke the real `trash` at all -- the actual incident this
# guards against is `trash ""` deleting the process's cwd. Shim `trash` to
# log its argv so we can assert it was never called with anything, not
# just that the process didn't crash.
TRASHSHIM=$(mktemp -d)
cat > "$TRASHSHIM/trash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$TRASH_LOG"
EOF
chmod +x "$TRASHSHIM/trash"
TRASH_LOG=$(mktemp)
export TRASH_LOG
PATH="$TRASHSHIM:$PATH" bash -c "
  . '$LIB'
  FAKE_HOME=''
  EXTRA_TRASH=('' '')
  _cleanup_trash
"
if [ ! -s "$TRASH_LOG" ]; then
  ok "_cleanup_trash with only empty targets never invokes trash at all"
else
  bad "_cleanup_trash invoked trash with: $(cat "$TRASH_LOG")"
fi
trash "$TRASHSHIM" "$TRASH_LOG" 2>/dev/null

# _cleanup_trash DOES invoke trash, once, with every real non-empty target
# (FAKE_HOME plus a mix of empty and real EXTRA_TRASH entries) -- proves the
# filter drops empties without also dropping real targets.
TRASHSHIM2=$(mktemp -d)
cat > "$TRASHSHIM2/trash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$TRASH_LOG2"
EOF
chmod +x "$TRASHSHIM2/trash"
TRASH_LOG2=$(mktemp)
export TRASH_LOG2
FAKE_REAL_HOME=$(mktemp -d)
FAKE_REAL_EXTRA=$(mktemp -d)
PATH="$TRASHSHIM2:$PATH" bash -c "
  . '$LIB'
  FAKE_HOME='$FAKE_REAL_HOME'
  EXTRA_TRASH=('' '$FAKE_REAL_EXTRA' '')
  _cleanup_trash
"
LOGGED=$(cat "$TRASH_LOG2" 2>/dev/null)
if printf '%s' "$LOGGED" | /usr/bin/grep -qF "$FAKE_REAL_HOME" && printf '%s' "$LOGGED" | /usr/bin/grep -qF "$FAKE_REAL_EXTRA" && ! printf '%s' "$LOGGED" | /usr/bin/grep -qx ''; then
  ok "_cleanup_trash trashes every real target, mixed with empties, without an empty argv element"
else
  bad "_cleanup_trash real-target pass failed: logged='$LOGGED'"
fi
trash "$TRASHSHIM2" "$TRASH_LOG2" "$FAKE_REAL_HOME" "$FAKE_REAL_EXTRA" 2>/dev/null

echo "tests/_lib/harness: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
