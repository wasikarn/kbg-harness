#!/usr/bin/env bash
# handoff-nudge.sh — SessionStart: nudge the model to suggest /mh:handoff after
# a compact, once per session. Advisory only, silent on any doubt.
#
# Registered with matcher "compact" (the opposite exclusion from
# session:handoff-surface's "startup|resume|clear") -- Claude Code's matcher
# already proves "compact" is a real, filterable SessionStart source, so this
# script never needs to check it itself.
#
# This is the one SessionStart hook in this repo that reads stdin: it needs
# session_id, which the official docs (code.claude.com/docs/en/hooks) list as
# a common input field on every hook event, SessionStart included. Every
# other SessionStart hook here avoids stdin because none of them need
# anything it carries, and reading it risks inheriting a backgrounded test
# runner's own stdin under scripts/run-gauntlet.sh -- a hang risk this script
# avoids by discipline, not avoidance: every test invocation supplies its own
# explicit stdin.
#
# "Once per session" is best-effort, not a hard guarantee: the atomic mkdir
# below prevents a *duplicate* claim within a session, nothing more -- if the
# final print fails after a successful claim, that nudge is lost for the
# session, and if $TMPDIR is cleared or rotates mid-session (a reboot, a
# temp-dir-rotating environment), the marker can vanish and the session may
# nudge again. Both accepted, not defended against, matching the "best-effort,
# not a guarantee" posture docs/adr/0002-mh-controlled-handoff-path.md already
# states for the read-side surfacer.
set -uo pipefail
umask 077

command -v python3 >/dev/null 2>&1 || exit 0

# session_id must be a real, non-empty JSON string -- not just present.
# json.load on malformed/empty stdin raises, caught below; a wrong-typed
# value (null, true, a number, an array/object) is deliberately NOT
# stringified into a fake session_id (Python's own str() would turn
# {"session_id":null} into the four-character string "None", which then
# passes a naive character-class regex as if it were a real id).
SESSION_ID=$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
sid = data.get("session_id") if isinstance(data, dict) else None
print(sid if isinstance(sid, str) and sid else "")
' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

# Character-class check, then explicitly reject "." and ".." even though
# both match the class -- neither is a real session id, and both are
# meaningful path components ("." is a no-op, ".." escapes one directory).
[[ "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || exit 0
[ "$SESSION_ID" != "." ] || exit 0
[ "$SESSION_ID" != ".." ] || exit 0

# Base directory: no trailing slash. A trailing-slash path resolves through
# a symlink before `-L` ever runs, silently defeating the very check below
# it -- confirmed live, this is not a hypothetical.
BASE="${TMPDIR:-/tmp}/mh-handoff-nudge"
mkdir -p "$BASE" 2>/dev/null
[ -d "$BASE" ] || exit 0
[ ! -L "$BASE" ] || exit 0

# /tmp on Linux is world-writable with the sticky bit: another local user
# could plant a directory here first. This marker carries no content and no
# secrets (unlike the actual handoff documents), so the bar is "don't get
# confused by something we don't own," not the heavier defenses
# skills/workflow/handoff/scripts/handoff-path.sh carries for real content.
OWNER_UID=$(stat -f '%u' "$BASE" 2>/dev/null || stat -c '%u' "$BASE" 2>/dev/null) || exit 0
[ "$OWNER_UID" = "$(id -u)" ] || exit 0

# The claim: one atomic mkdir, and it IS the print-gate -- no separate
# exists-check before it, no distinction needed between "already claimed"
# and "a real failure" (permission denied, $BASE vanished). Both want the
# same silent, no-nudge outcome. This also replaces a would-be flock: unlike
# hooks/sensors/failure-diagnose-nudge.py (which can fire many times a
# second from parallel tool-call failures), a real SessionStart fires
# exactly once per actual session-start event, so mkdir's own atomicity is
# the whole race guard needed.
mkdir "$BASE/$SESSION_ID" 2>/dev/null || exit 0

printf '<mh-handoff-nudge>\n' 2>/dev/null
printf 'This session was just compacted -- some earlier context is now summarized, not verbatim. If\n' 2>/dev/null
printf 'there is still significant work in flight, mention to the user in your next reply that running\n' 2>/dev/null
printf '/mh:handoff now would checkpoint it before the next compaction or session end.\n' 2>/dev/null
printf '</mh-handoff-nudge>\n' 2>/dev/null

exit 0
