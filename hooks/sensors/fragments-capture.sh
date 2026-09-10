#!/usr/bin/env bash
# fragments-capture.sh — PostToolUse (Write|Edit): if this session is armed
# (hooks/sensors/fragments-arm.sh) and this write plausibly targets a
# writing-fragments document, record a durable pointer to it. Never touches,
# copies, or inlines the document's own content -- only a path pointer and a
# change-detection snapshot. Never prints anything. Advisory only, silent on
# any doubt. Full design: docs/adr/0003-writing-fragments-pointer-capture.md.
set -uo pipefail
umask 077

BASE="${TMPDIR:-/tmp}/mh-fragments-arm"

# Readdir gate before anything else, before stdin is even read: one
# opendir, zero subprocesses, in the overwhelming majority of invocations
# (no session anywhere is armed). Deliberately not session-scoped at this
# stage -- scoping here would require parsing stdin first, exactly the cost
# this gate exists to skip.
shopt -s nullglob
set -- "$BASE"/*
[ $# -gt 0 ] || exit 0
shopt -u nullglob

command -v python3 >/dev/null 2>&1 || exit 0

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../scripts/_lib/fragments-state.sh"

PAYLOAD=$(cat)

# Parse once: validated session_id (same discipline as fragments-arm.sh),
# tool_name, tool_input.file_path, whether content starts with an H1 (Write
# only -- Edit payloads carry old_string/new_string, not content), cwd.
RESULT=$(printf '%s' "$PAYLOAD" | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None

sid = data.get("session_id") if isinstance(data, dict) else None
if not isinstance(sid, str) or sid in (".", "..") or not re.fullmatch(r"[A-Za-z0-9._-]+", sid):
    sid = ""

tool_name = data.get("tool_name") if isinstance(data, dict) else None
if not isinstance(tool_name, str):
    tool_name = ""

cwd = data.get("cwd") if isinstance(data, dict) else None
if not isinstance(cwd, str):
    cwd = ""

tool_input = data.get("tool_input") if isinstance(data, dict) else None
file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
if not isinstance(file_path, str):
    file_path = ""

h1 = "0"
if tool_name == "Write" and isinstance(tool_input, dict):
    content = tool_input.get("content")
    if isinstance(content, str) and re.match(r"#[ \t]", content):
        h1 = "1"

print(sid)
print(tool_name)
print(cwd)
print(h1)
print(file_path)
' 2>/dev/null)
[ -n "$RESULT" ] || exit 0

SESSION_ID=$(printf '%s\n' "$RESULT" | sed -n '1p')
TOOL_NAME=$(printf '%s\n' "$RESULT" | sed -n '2p')
CWD=$(printf '%s\n' "$RESULT" | sed -n '3p')
HAS_H1=$(printf '%s\n' "$RESULT" | sed -n '4p')
FILE_PATH=$(printf '%s\n' "$RESULT" | tail -n +5)

[ -n "$SESSION_ID" ] || exit 0
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac
[ -n "$FILE_PATH" ] || exit 0

# Find this session's live marker via the current-generation pointer, not a
# glob (round-4 finding: "newest live marker by mtime" let a claimed
# generation drop out of the glob, making an older, already-superseded
# marker reselectable). No fallback to scanning for any other marker.
POINTER="$BASE/${SESSION_ID}.current"
[ -f "$POINTER" ] && [ ! -L "$POINTER" ] || exit 0
SUFFIX=$(head -c 64 -- "$POINTER" 2>/dev/null)
case "$SUFFIX" in
  '') exit 0 ;;
  *[!A-Za-z0-9]*) exit 0 ;;
esac

MARKER="$BASE/${SESSION_ID}.${SUFFIX}"
[ -d "$MARKER" ] && [ ! -L "$MARKER" ] || exit 0

# Window-expiry sweep, scoped to exactly the one generation the pointer
# names -- there is never another candidate marker to consider.
NOW=$(date +%s)
MTIME=$(stat -f '%m' "$MARKER" 2>/dev/null || stat -c '%Y' "$MARKER" 2>/dev/null || echo 0)
AGE=$((NOW - MTIME))
if [ "$AGE" -gt 1800 ]; then
  rmdir "$MARKER" 2>/dev/null
  rm -f "${MARKER}.candidate" 2>/dev/null
  exit 0
fi

CANDIDATE_FILE="${MARKER}.candidate"

# Plausibility check. Candidate present -> match iff file_path resolves to
# the same canonical path as the candidate text; no heuristic fallback runs
# at all in this case. Candidate absent -> fall back to the heuristic
# (round-1/2/3 findings: this is the only tier where an unrelated .md/H1
# write is accepted, a named gap, not a bug).
CANONICAL_TARGET=""
if [ -f "$FILE_PATH" ] || [ -e "$FILE_PATH" ]; then
  CANONICAL_TARGET=$(cd -P -- "$(dirname -- "$FILE_PATH")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename -- "$FILE_PATH")")
fi
[ -n "$CANONICAL_TARGET" ] || CANONICAL_TARGET="$FILE_PATH"

MATCH=0
if [ -s "$CANDIDATE_FILE" ] && [ ! -L "$CANDIDATE_FILE" ]; then
  CAND_TEXT=$(cat -- "$CANDIDATE_FILE" 2>/dev/null)
  CAND_RESOLVED="$CAND_TEXT"
  # ~ expansion for a typed "~/notes/x.md" candidate -- the shell never
  # expands the sidecar file's own contents, so this is done explicitly.
  # shellcheck disable=SC2088  # this is a case PATTERN match, not a tilde
  # left unexpanded inside a quoted expansion -- $HOME is used on the RHS.
  case "$CAND_TEXT" in
    '~/'*) CAND_RESOLVED="$HOME/${CAND_TEXT#~/}" ;;
    '~') CAND_RESOLVED="$HOME" ;;
  esac
  # A relative candidate (e.g. "./frags.md", typed with no leading /) must
  # anchor on the payload's own $CWD, not this process's ambient cwd -- the
  # two are not guaranteed to be the same thing, and ROOT resolution above
  # already uses $CWD as its source of truth for exactly this reason.
  # Deep-audit finding, live-reproduced: without this, a relative candidate
  # silently failed to match a real write to the exact intended file.
  case "$CAND_RESOLVED" in
    /*) : ;;
    *) [ -n "$CWD" ] && CAND_RESOLVED="$CWD/$CAND_RESOLVED" ;;
  esac
  if [ -e "$CAND_RESOLVED" ]; then
    CAND_CANONICAL=$(cd -P -- "$(dirname -- "$CAND_RESOLVED")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename -- "$CAND_RESOLVED")")
  else
    CAND_CANONICAL="$CAND_RESOLVED"
  fi
  [ -n "$CAND_CANONICAL" ] && [ "$CAND_CANONICAL" = "$CANONICAL_TARGET" ] && MATCH=1
else
  # Heuristic tier: absolute path, .md/.markdown extension, not under
  # $HOME/.claude/ or $CLAUDE_PLUGIN_ROOT, H1-required for Write, extension
  # alone sufficient for Edit.
  case "$CANONICAL_TARGET" in
    /*) : ;;
    *) CANONICAL_TARGET="" ;;
  esac
  case "$CANONICAL_TARGET" in
    *.md|*.markdown) : ;;
    *) CANONICAL_TARGET="" ;;
  esac
  if [ -n "$CANONICAL_TARGET" ]; then
    CLAUDE_DIR_REAL=$(cd -P -- "$HOME/.claude" 2>/dev/null && pwd)
    PLUGIN_ROOT_REAL=""
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && PLUGIN_ROOT_REAL=$(cd -P -- "$CLAUDE_PLUGIN_ROOT" 2>/dev/null && pwd)
    case "$CANONICAL_TARGET" in
      "$CLAUDE_DIR_REAL"/*) CANONICAL_TARGET="" ;;
    esac
    if [ -n "$PLUGIN_ROOT_REAL" ]; then
      case "$CANONICAL_TARGET" in
        "$PLUGIN_ROOT_REAL"/*) CANONICAL_TARGET="" ;;
      esac
    fi
  fi
  if [ -n "$CANONICAL_TARGET" ]; then
    case "$TOOL_NAME" in
      Write) [ "$HAS_H1" = "1" ] && MATCH=1 ;;
      Edit)  MATCH=1 ;;
    esac
  fi
fi

[ "$MATCH" -eq 1 ] || exit 0

# Claim: rename $MARKER -> ${MARKER}.claimed. Since $MARKER already carries
# this invocation's own unique mktemp suffix, ${MARKER}.claimed can never
# coincide with any other invocation's claim name, so this rename can never
# land on a pre-existing directory (round-3 finding, closed structurally by
# round-3's per-invocation unique naming). Exactly one concurrent process
# wins; losers see the source gone and exit before ever attempting a
# publish. The pointer itself is never touched here -- it still names the
# same suffix, so a later write that reads it will find $MARKER gone and
# correctly treat this generation as no-longer-armed, never falling back to
# any other generation.
CLAIMED="${MARKER}.claimed"
mv "$MARKER" "$CLAIMED" 2>/dev/null || exit 0

# Publish: create-only, the exact handoff-path.sh --publish sequence.
# Project root must be resolved to the git repo root (matching
# fragments-arm.sh / handoff-path.sh) before scoping -- using the raw cwd
# directly would scope this record to a subdirectory instead of the
# project root whenever the write happened from one.
ROOT=$(cd -- "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) \
  || ROOT=$(cd -P -- "$CWD" 2>/dev/null && pwd)
DOCS_DIR=""
[ -n "$ROOT" ] && DOCS_DIR=$(fragments_docs_dir "$ROOT" 2>/dev/null)
if [ -z "$DOCS_DIR" ]; then
  mv "$CLAIMED" "$MARKER" 2>/dev/null
  exit 0
fi

DOC_ID=$(python3 -c '
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])
' "$CANONICAL_TARGET" 2>/dev/null)
[ -n "$DOC_ID" ] || { mv "$CLAIMED" "$MARKER" 2>/dev/null; exit 0; }

DEST="$DOCS_DIR/$DOC_ID.json"
if [ -e "$DEST" ]; then
  # Already captured -- nothing to overwrite, never clobber an existing
  # surfaced_snapshot. Counts as success.
  rm -f "${MARKER}.candidate" 2>/dev/null
  rmdir "$CLAIMED" 2>/dev/null
  exit 0
fi

TMP_DOC=$(mktemp "$DOCS_DIR/.doc.XXXXXX" 2>/dev/null)
if [ -z "$TMP_DOC" ]; then
  mv "$CLAIMED" "$MARKER" 2>/dev/null
  exit 0
fi

CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
python3 -c '
import json, sys
path, sid, ts, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {"version": 1, "path": path, "captured_at": ts, "captured_session": sid, "surfaced_snapshot": None}
with open(out, "w") as f:
    json.dump(doc, f)
' "$CANONICAL_TARGET" "$SESSION_ID" "$CAPTURED_AT" "$TMP_DOC" 2>/dev/null
if [ ! -s "$TMP_DOC" ]; then
  rm -f "$TMP_DOC" 2>/dev/null
  mv "$CLAIMED" "$MARKER" 2>/dev/null
  exit 0
fi

if [ -e "$DEST" ]; then
  # Lost a race to another writer for the same path -- fine, already
  # captured.
  rm -f "$TMP_DOC" 2>/dev/null
  rm -f "${MARKER}.candidate" 2>/dev/null
  rmdir "$CLAIMED" 2>/dev/null
  exit 0
fi
mv -n "$TMP_DOC" "$DEST" 2>/dev/null
if [ -e "$TMP_DOC" ]; then
  # mv -n silently no-op'd -- genuine publish failure. Restore this exact
  # invocation's arm (sidecar untouched) so a later qualifying write in the
  # same window can retry it.
  rm -f "$TMP_DOC" 2>/dev/null
  mv "$CLAIMED" "$MARKER" 2>/dev/null
  exit 0
fi
if [ -f "$DEST" ] && [ ! -L "$DEST" ]; then
  chmod 600 "$DEST" 2>/dev/null
fi

# Success: fully and correctly disarmed for this invocation.
rm -f "${MARKER}.candidate" 2>/dev/null
rmdir "$CLAIMED" 2>/dev/null

exit 0
