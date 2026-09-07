#!/usr/bin/env bash
# find-transcript.sh — print the path and byte size of THIS session's own
# Claude Code transcript (.jsonl), for mh:learn to mine.
#
# CC stores transcripts at ~/.claude/projects/<cwd-with-/-as->/<session-id>.jsonl
# (project path with every "/" replaced by "-", NOT lowercased). The session
# id is read from the native CLAUDE_CODE_SESSION_ID env var, not "latest file
# by mtime" — this repo runs concurrent sessions on a shared tree (often 50+
# transcripts in one project dir at a time), so mtime-latest would frequently
# pick a *different* session's transcript, mining the wrong conversation into
# memory. Prints "<path> <bytes>" on stdout, or a reason on stderr + exit 1.
set -uo pipefail

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$SESSION_ID" ] || { echo "find-transcript: CLAUDE_CODE_SESSION_ID is not set — cannot determine this session's own transcript; ask the operator for the transcript path directly" >&2; exit 1; }

# Deep-audit 2026-09-07: the real runtime's own slug function (confirmed in
# the installed CC binary's own source) replaces EVERY non-alphanumeric
# character with "-", not just "/". This repo's own checkout path (letters
# and hyphens only) happens to produce an identical result under either
# rule, which is exactly why the old "/"-only rule went uncaught. A project
# path >200 chars additionally gets truncated with a hash suffix in the real
# runtime, using an internal hash function this script has no way to
# replicate -- rather than silently guess wrong for that case, fail loud.
CWD="${1:-$PWD}"
if [ "${#CWD}" -gt 200 ]; then
  echo "find-transcript: project path is over 200 chars ($CWD) -- the real runtime truncates and hashes long paths, which this script cannot replicate; ask the operator for the transcript path directly" >&2
  exit 1
fi
SLUG=$(printf '%s' "$CWD" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')
DIR="$HOME/.claude/projects/$SLUG"
TARGET="$DIR/$SESSION_ID.jsonl"

# Claude Code deletes transcripts along with sessions 30 days after the last
# activity (settings.json `cleanupPeriodDays`, default 30). A not-found here
# on an old session may just mean it was already swept, not a lookup bug —
# say so if the skill surfaces this to the user.
[ -f "$TARGET" ] || { echo "find-transcript: no transcript at $TARGET (session may be new, or already swept)" >&2; exit 1; }

size=$(wc -c < "$TARGET" | tr -d ' ')
printf '%s %s\n' "$TARGET" "$size"
