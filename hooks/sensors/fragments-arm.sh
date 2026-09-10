#!/usr/bin/env bash
# fragments-arm.sh — UserPromptSubmit: arm a per-invocation marker when the
# user's prompt invokes mattpocock-skills:writing-fragments, so a qualifying
# write shortly after can be captured as a pointer
# (hooks/sensors/fragments-capture.sh). Advisory only, silent on any doubt.
# Full design and every round-N finding this script encodes:
# docs/adr/0003-writing-fragments-pointer-capture.md.
#
# UserPromptSubmit is the mechanism that replaced an originally-planned
# PreToolUse:Skill hook -- confirmed dead for a user-typed slash command
# (never produces a Skill tool_use event at all, regardless of
# disable-model-invocation). See the ADR for the full evidence chain.
#
# Reads stdin once (PAYLOAD=$(cat)) -- unlike every SessionStart hook in
# this repo, UserPromptSubmit hooks are expected to read it; there is no
# backgrounded-test-runner stdin-inheritance hang risk here the way there is
# for SessionStart under scripts/run-gauntlet.sh.
#
# A non-zero exit (or exit 2) here BLOCKS the user's own prompt -- every
# failure path below is therefore a silent `exit 0`, never anything else.
set -uo pipefail
umask 077

command -v python3 >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat)

# Cost gate: a pure-bash substring check before any subprocess. Costs
# nothing on the overwhelming majority of ordinary prompts. A false
# positive here is rechecked properly by the real regex below; a false
# negative is impossible since the literal string must appear in the JSON
# prompt text for a real match to exist at all.
case "$PAYLOAD" in
  *writing-fragments*) ;;
  *) exit 0 ;;
esac

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../scripts/_lib/fragments-state.sh"

# Single python3 call: validates session_id exactly like handoff-nudge.sh
# (character-class + ./.. rejection, in python, against the untruncated
# string -- bash command substitution silently mangles a trailing newline
# or an embedded NUL before a bash-side check would ever see it), matches
# the skill-invocation regex against `prompt`, and extracts an optional
# candidate path from whatever follows it in the same prompt. Output:
# session_id, match flag, cwd -- each on its own line -- then the (possibly
# multi-line, possibly empty) candidate text as everything remaining.
RESULT=$(printf '%s' "$PAYLOAD" | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None

sid = data.get("session_id") if isinstance(data, dict) else None
if not isinstance(sid, str) or sid in (".", "..") or not re.fullmatch(r"[A-Za-z0-9._-]+", sid):
    sid = ""

cwd = data.get("cwd") if isinstance(data, dict) else None
if not isinstance(cwd, str):
    cwd = ""

prompt = data.get("prompt") if isinstance(data, dict) else None
if not isinstance(prompt, str):
    prompt = ""

m = re.match(r"\s*[/@$](mattpocock-skills:)?writing-fragments(\s|$)", prompt)
matched = bool(m and sid)

candidate = ""
if matched:
    rest = prompt[m.end():].strip()
    if rest and "\x00" not in rest:
        candidate = rest

print(sid)
print("1" if matched else "0")
print(cwd)
print(candidate)
' 2>/dev/null)
[ -n "$RESULT" ] || exit 0

SESSION_ID=$(printf '%s\n' "$RESULT" | sed -n '1p')
MATCHED=$(printf '%s\n' "$RESULT" | sed -n '2p')
CWD=$(printf '%s\n' "$RESULT" | sed -n '3p')
CANDIDATE=$(printf '%s\n' "$RESULT" | tail -n +4)

[ "$MATCHED" = "1" ] && [ -n "$SESSION_ID" ] || exit 0

# Base directory: no trailing slash (the symlink-check-defeat lesson
# handoff-nudge.sh's own compliance-audit round found).
BASE="${TMPDIR:-/tmp}/mh-fragments-arm"
mkdir -p "$BASE" 2>/dev/null
[ -d "$BASE" ] || exit 0
[ ! -L "$BASE" ] || exit 0

owner_ok() {
  local uid
  uid=$(stat -f '%u' "$BASE" 2>/dev/null || stat -c '%u' "$BASE" 2>/dev/null) || return 1
  [ "$uid" = "$(id -u 2>/dev/null)" ]
}
owner_ok || exit 0

# Arm marker: every invocation gets its own uniquely-named marker
# (mktemp -d's random suffix), so no two invocations -- however they
# overlap in time or however one of them fails -- can ever share a name to
# collide over (round-3 finding: a fixed-name marker/claim let `mv` nest a
# new claim inside an old one instead of failing). Kept empty (nothing
# written inside it) so rmdir/rename against it never fails on "not empty."
MARKER=$(mktemp -d "$BASE/${SESSION_ID}.XXXXXX" 2>/dev/null) || exit 0
SUFFIX="${MARKER##*.}"

# Candidate sidecar, a sibling FILE sharing the same unique suffix -- never
# nested inside the marker (a round-2 finding: storing it as a file inside
# the marker directory broke every rmdir call). Written -- fully, including
# leaving it absent when no candidate was typed -- before the pointer
# publish below, which is the step that makes this generation visible to
# Hook 2 at all (round-4 finding: a generation must never be selectable
# before its candidate, if any, has finished writing).
if [ -n "$CANDIDATE" ]; then
  printf '%s' "$CANDIDATE" > "${MARKER}.candidate" 2>/dev/null
fi

# Current-generation pointer, published LAST -- only after the marker and
# its optional candidate are both fully written. A plain file (never a
# directory), so `mv` onto it always replaces atomically with no risk of
# the directory-nesting hazard a fixed-name marker/claim had in earlier
# rounds (round-4 finding: Hook 2 must select only the ONE generation this
# pointer names, never fall back to scanning for any other marker).
LOCKDIR="$BASE/${SESSION_ID}.lock"
POINTER="$BASE/${SESSION_ID}.current"
TMP_PTR=$(mktemp "$BASE/.ptr.XXXXXX" 2>/dev/null) || { rmdir "$MARKER" 2>/dev/null; rm -f "${MARKER}.candidate" 2>/dev/null; exit 0; }
printf '%s' "$SUFFIX" > "$TMP_PTR" 2>/dev/null
if fragments_lock_acquire "$LOCKDIR"; then
  mv "$TMP_PTR" "$POINTER" 2>/dev/null
  fragments_lock_release "$LOCKDIR"
else
  # Lock still contended after the bounded retry (round-5 finding: the
  # pointer sweep and a fresh publish share this lock). Arming must never
  # hang or silently fail outright -- publish anyway. The residual (a sweep
  # racing this exact publish, unowned by a live process) is accepted and
  # bounded, same posture as the rest of this design.
  mv "$TMP_PTR" "$POINTER" 2>/dev/null
fi

# Best-effort known-path injection below: never blocks arming above, and
# any failure here (no git repo, no existing record) is silent.
ROOT=$(cd -- "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) \
  || ROOT=$(cd -P -- "$CWD" 2>/dev/null && pwd)
[ -n "$ROOT" ] || exit 0

DOCS_DIR=$(fragments_docs_dir "$ROOT" 2>/dev/null) || exit 0
[ -d "$DOCS_DIR" ] || exit 0

# Most-recently-captured record on file for this project, if any -- read
# via python3 so a malformed record can never crash this script.
KNOWN=$(python3 -c '
import glob, json, os, sys
docs_dir = sys.argv[1]
best = None
for f in glob.glob(os.path.join(docs_dir, "*.json")):
    try:
        with open(f) as fh:
            rec = json.load(fh)
    except Exception:
        continue
    if not isinstance(rec, dict):
        continue
    path = rec.get("path")
    captured_at = rec.get("captured_at")
    if not isinstance(path, str) or not path:
        continue
    key = captured_at if isinstance(captured_at, str) else ""
    if best is None or key > best[1]:
        best = (path, key)
if best:
    print(best[0])
' "$DOCS_DIR" 2>/dev/null)
[ -n "$KNOWN" ] || exit 0
[ -f "$KNOWN" ] && [ ! -L "$KNOWN" ] || exit 0

TITLE=$(head -c 200 -- "$KNOWN" 2>/dev/null | head -n 1)
case "$TITLE" in
  '# '*) TITLE="${TITLE#\# }" ;;
  *) TITLE="untitled" ;;
esac

SAFE_PATH=$(fragments_sanitize "$KNOWN" "path" 0)
SAFE_TITLE=$(fragments_sanitize "$TITLE" "title" 120)
[ -n "$SAFE_PATH" ] && [ -n "$SAFE_TITLE" ] || exit 0

printf '<mh-fragments-known>\n' 2>/dev/null
printf 'A writing-fragments file already exists for this project: %s ("%s").\n' "$SAFE_PATH" "$SAFE_TITLE" 2>/dev/null
printf 'Offer to continue there before asking the user where to save. Advisory only -- the user decides.\n' 2>/dev/null
printf '</mh-fragments-known>\n' 2>/dev/null

exit 0
