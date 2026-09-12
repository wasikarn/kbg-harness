#!/usr/bin/env bash
# Behavioral tests for hooks/gates/_journal.py, restored 2026-09-12 after commit
# 2cac98c8 deleted the central-dispatcher version with no replacement. Covers:
# a deny verdict journals a row, an allow-only payload adds none (volume
# control), the fail-safe (an unwritable journal path must never change the
# gate's own exit code/stdout, using an ENOTDIR fixture that is uid-independent
# -- a chmod-based fixture is a no-op as root, which this repo's own podman
# ubuntu:24.04 dry-run lane runs as), and a gate-id drift guard (each gate's
# hardcoded GATE_ID constant must actually exist in hooks/hook-registry.json).
# Run standalone: bash tests/hooks/test-gate-journal.sh
set -uo pipefail

# This file tests the HOME-fallback path directly (cases 1-4) and the
# override explicitly (case 5) -- unset any ambient MH_GATE_JOURNAL_PATH
# first, since scripts/run-gauntlet.sh's hook-test layer sets one for the
# whole suite and it would otherwise silently win over every HOME= prefix
# below, making cases 1-4 write nowhere the assertions look.
unset MH_GATE_JOURNAL_PATH

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || rm -rf "$WORK"' EXIT

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"session_id":"sess-journal-test"}))' "$1"
}

payload_edit() { # payload_edit <file_path> <old_string> <new_string>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]},"session_id":"sess-journal-test"}))' "$1" "$2" "$3"
}

echo "=== gate-verdict journal ==="
cd "$ROOT" || exit 1

# --- Case 1: a deny verdict writes a journal row ---
HOME="$WORK/case1"; mkdir -p "$HOME"
JOURNAL="$HOME/.local/share/kbg/metrics/gate-decisions.jsonl"
payload_bash "rm -rf /" | HOME="$HOME" bash hooks/gates/irrecoverable.sh >/dev/null 2>&1; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "irrecoverable.sh denies rm -rf / (rc=2)" "$ok"
ok=1
[ -f "$JOURNAL" ] && /usr/bin/grep -q '"decision": "deny"' "$JOURNAL" && /usr/bin/grep -q '"id": "gate:bash:irrecoverable"' "$JOURNAL" && ok=0
check "deny verdict journaled with correct id/decision" "$ok"

# --- Case 2: an allow-only payload adds no row (volume control) ---
HOME="$WORK/case2"; mkdir -p "$HOME"
JOURNAL2="$HOME/.local/share/kbg/metrics/gate-decisions.jsonl"
payload_bash "ls -la" | HOME="$HOME" bash hooks/gates/irrecoverable.sh >/dev/null 2>&1; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "irrecoverable.sh allows ls -la (rc=0)" "$ok"
ok=1; [ ! -s "$JOURNAL2" ] && ok=0
check "allow-only dispatch does not add a journal row" "$ok"

# --- Case 3: the fail-safe. Point HOME at a path whose PARENT is a regular
# file, so os.makedirs raises ENOTDIR regardless of uid (a chmod-based
# unwritable-directory fixture is a no-op as root). Assert BOTH the gate's own
# exit code/stdout is unchanged AND the write genuinely failed (no journal
# file anywhere under the isolated HOME) -- either assertion alone can't tell
# "the write failed safely" from "the write never happened to fail". ---
NOT_A_DIR="$WORK/not-a-dir"
: > "$NOT_A_DIR"
BROKEN_HOME="$NOT_A_DIR/sub"

payload_bash "rm -rf /" | HOME="$BROKEN_HOME" bash hooks/gates/irrecoverable.sh >/dev/null 2>&1; deny_broken_rc=$?
ok=1; [ "$deny_broken_rc" -eq 2 ] && ok=0
check "deny verdict unchanged (still exit 2) when the journal path is unwritable (ENOTDIR)" "$ok"

TESTFILE="$WORK/tests/hooks/test-sample.sh"
mkdir -p "$(dirname "$TESTFILE")"
printf 'check "case one" "$ok1"\n' > "$TESTFILE"
ask_baseline=$(payload_edit "$TESTFILE" 'check "case one" "$ok1"' '' | HOME="$WORK/case1-baseline" bash hooks/gates/test-integrity.sh 2>/dev/null)
ask_broken=$(payload_edit "$TESTFILE" 'check "case one" "$ok1"' '' | HOME="$BROKEN_HOME" bash hooks/gates/test-integrity.sh 2>/dev/null)
ok=1; [ "$ask_broken" = "$ask_baseline" ] && [ -n "$ask_broken" ] && ok=0
check "ask verdict stdout byte-identical whether journal succeeds or fails" "$ok"

# NOT_A_DIR is a regular file, so BROKEN_HOME (a path underneath it) can never
# be created by os.makedirs -- confirm it genuinely never came into existence,
# proving the write really failed rather than the assertion above being
# trivially true either way.
ok=1; [ ! -e "$BROKEN_HOME" ] && ok=0
check "journal write under the unwritable path genuinely failed (no dir ever created)" "$ok"

# --- Case 4: gate-id drift guard -- every gate's hardcoded GATE_ID constant
# must actually appear in hooks/hook-registry.json (no drift-detection for
# this exists anywhere else in the harness; check 73 diffs hooks.json against
# the registry but never looks inside a gate .py). ---
REGISTRY="$ROOT/hooks/hook-registry.json"
ok=0
for f in "$ROOT"/hooks/gates/*.py; do
  [ "$(basename "$f")" = "_journal.py" ] && continue
  id=$(/usr/bin/grep -oE 'GATE_ID = "[^"]+"' "$f" | head -1 | sed 's/GATE_ID = "//; s/"$//')
  [ -z "$id" ] && continue  # this gate has no journal wiring (none expected today)
  /usr/bin/grep -q "\"$id\"" "$REGISTRY" || { echo "  drift: $f's GATE_ID=$id not found in hook-registry.json" >&2; ok=1; }
done
check "every gate's GATE_ID literal exists in hook-registry.json" "$ok"

# --- Case 5: MH_GATE_JOURNAL_PATH override is honored (the mechanism
# scripts/run-gauntlet.sh's hook-test layer relies on, instead of swapping
# HOME wholesale -- an earlier version of that fix broke PyYAML-dependent
# tests, since PyYAML resolves via the real HOME's user site-packages). ---
OVERRIDE_PATH="$WORK/case5/custom-journal.jsonl"
payload_bash "rm -rf /" | env -u HOME MH_GATE_JOURNAL_PATH="$OVERRIDE_PATH" bash hooks/gates/irrecoverable.sh >/dev/null 2>&1; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "irrecoverable.sh still denies with HOME unset, override path set" "$ok"
ok=1
[ -f "$OVERRIDE_PATH" ] && /usr/bin/grep -q '"decision": "deny"' "$OVERRIDE_PATH" && ok=0
check "MH_GATE_JOURNAL_PATH override is honored, ignoring HOME entirely" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
