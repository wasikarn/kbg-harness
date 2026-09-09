#!/usr/bin/env bash
# Unit tests for skills/workflow/handoff/scripts/handoff-path.sh — the
# atomic-publish helper behind mh:handoff. Every case here traces back to a
# specific Codex round-N finding from the plan review that shaped this
# script; see docs/adr/0002-mh-controlled-handoff-path.md for the full history.
# Run standalone: bash tests/skills/handoff/test-handoff-path.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/workflow/handoff/scripts/handoff-path.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

FAKE_HOME=$(mktemp -d)
trap 'trash "$FAKE_HOME" 2>/dev/null || true' EXIT

# All calls run from this repo's own checkout, so ROOT resolution exercises
# the real git-repo-root branch, not the no-git fallback (covered separately
# below with a fixture repo).
run() { HOME="$FAKE_HOME" bash "$SCRIPT" "$@"; }

# --- --dir creates nothing ---
DIR_OUT=$(run --dir 2>/dev/null)
if [ -n "$DIR_OUT" ] && [ ! -e "$FAKE_HOME/.claude/state/mh-handoffs" ]; then
  ok "--dir prints a path but creates no directory"
else
  bad "--dir should print a path without creating anything; state dir exists=$([ -e "$FAKE_HOME/.claude/state/mh-handoffs" ] && echo yes || echo no)"
fi

# --- default allocates a staging path, and staging/ is 0700 ---
P1=$(run)
rc=$?
if [ "$rc" -eq 0 ] && [ -n "$P1" ]; then
  STAGING_DIR=$(dirname "$P1")
  MODE=$(stat -f '%Lp' "$STAGING_DIR" 2>/dev/null || stat -c '%a' "$STAGING_DIR" 2>/dev/null)
  if [ "$MODE" = "700" ]; then
    ok "default call allocates a staging path with staging/ at 0700"
  else
    bad "expected staging/ mode 700, got $MODE"
  fi
else
  bad "default call failed (rc=$rc)"
fi

# --- Codex round 2, P1: two concurrent allocations before either writes
# anything must get distinct staging paths (the real race, not just distinct
# publish targets) ---
P2=$(run)
if [ "$P1" != "$P2" ] && [ -n "$P2" ]; then
  ok "two allocations before either writes get distinct staging paths"
else
  bad "expected distinct staging paths, got P1=$P1 P2=$P2"
fi

# --- Codex round 3, P1, reproduced live against the real macOS mktemp:
# staging basenames must actually be randomized, not literal 'XXXXXX' ---
if [[ "$(basename "$P1")" != *XXXXXX* ]] && [[ "$(basename "$P2")" != *XXXXXX* ]]; then
  ok "mktemp actually randomizes the staging suffix (not a literal XXXXXX)"
else
  bad "staging name still contains literal XXXXXX -- mktemp template's X's are not trailing: $P1"
fi

# --- staging filenames are hidden from the hook's handoff-*.md glob on two
# independent counts: leading dot, and no .md extension at all ---
B1="$(basename "$P1")"
case "$B1" in
  handoff-*.md) bad "staging name matches the hook's handoff-*.md glob: $B1" ;;
  .*) [[ "$B1" == *.md ]] && bad "staging name has a leading dot but still ends .md: $B1" || ok "staging name is glob-invisible (leading dot, no .md extension)" ;;
  *) bad "staging name has no leading dot: $B1" ;;
esac

# --- publish: content survives, published file is 0600, name is <base>.md
# with the leading dot stripped ---
printf 'hello handoff\n' > "$P1"
PUB1=$(run --publish "$P1")
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$PUB1" ] && [ "$(cat "$PUB1")" = "hello handoff" ]; then
  ok "publish moves staged content into pending/ intact"
else
  bad "publish failed or content mismatch (rc=$rc, PUB1=$PUB1)"
fi
EXPECTED_BASE="handoff${B1#.handoff}.md"
if [ "$(basename "$PUB1")" = "$EXPECTED_BASE" ]; then
  ok "published basename strips the leading dot and appends .md, preserving the random suffix"
else
  bad "expected published basename $EXPECTED_BASE, got $(basename "$PUB1")"
fi
PUB_MODE=$(stat -f '%Lp' "$PUB1" 2>/dev/null || stat -c '%a' "$PUB1" 2>/dev/null)
if [ "$PUB_MODE" = "600" ]; then
  ok "published file is 0600"
else
  bad "expected published file mode 600, got $PUB_MODE"
fi
if [ ! -e "$P1" ]; then
  ok "staged file no longer exists at its staging path after publish"
else
  bad "staged file still present at $P1 after a reported-successful publish"
fi

# --- publish is atomic: the hook's glob sees either nothing or a complete
# file, never a partial one (this is a structural property of mv, asserted
# here by checking the published file's content is the full, exact write) ---
LONG_CONTENT=$(printf 'line %s\n' $(seq 1 500))
P3=$(run)
printf '%s' "$LONG_CONTENT" > "$P3"
PUB3=$(run --publish "$P3")
if [ "$(cat "$PUB3")" = "$LONG_CONTENT" ]; then
  ok "a larger document publishes with its exact full content, nothing partial"
else
  bad "published content does not match what was staged for a larger document"
fi

# --- Codex round 3, P2, reproduced live: mv -n exits 0 on a destination
# collision without moving anything -- the helper must detect this as a
# real, loud failure, not report a false success ---
P5=$(run)
printf 'second content, would silently clobber if not for the postcondition check\n' > "$P5"
# The published name is a pure function of the staging basename (strip the
# leading dot, append .md) -- derive it the same way the script does, then
# pre-place a document there so publish must collide with it.
PENDING_DIR="$(dirname "$(dirname "$P5")")/pending"
mkdir -p "$PENDING_DIR"
P5_EXPECTED_DEST="$PENDING_DIR/$(basename "$P5" | sed 's/^\.//').md"
printf 'pre-existing document, must survive untouched\n' > "$P5_EXPECTED_DEST"
if OUT=$(run --publish "$P5" 2>&1); then
  bad "publish onto an existing destination reported success: $OUT"
else
  if [ "$(cat "$P5_EXPECTED_DEST")" = "pre-existing document, must survive untouched" ] && [ -f "$P5" ]; then
    ok "publish onto an existing destination fails loud, leaves the pre-existing document untouched and the staged draft in place"
  else
    bad "publish onto an existing destination failed loud but corrupted state (dest or source not as expected)"
  fi
fi

# --- --publish rejects a path outside this project's staging dir ---
OUTSIDE=$(mktemp)
printf 'not staged here\n' > "$OUTSIDE"
if OUT=$(run --publish "$OUTSIDE" 2>&1); then
  bad "publish accepted a path outside staging/: $OUT"
else
  ok "publish refuses a path outside this project's staging dir"
fi
trash "$OUTSIDE" 2>/dev/null || true

# --- --publish rejects a symlink, even one pointing at a real file inside
# staging/ (defense in depth against a planted symlink) ---
REAL_TARGET=$(run)
printf 'real content\n' > "$REAL_TARGET"
SYMLINK_STAGE="$(dirname "$REAL_TARGET")/.handoff-symlink-test.XXXXXX"
SYMLINK_STAGE="${SYMLINK_STAGE//XXXXXX/lnk}"
ln -s "$REAL_TARGET" "$SYMLINK_STAGE"
if OUT=$(run --publish "$SYMLINK_STAGE" 2>&1); then
  bad "publish accepted a symlink: $OUT"
else
  ok "publish refuses a symlink even when it points at a real file inside staging/"
fi

# --- no-git fallback: outside any git repo, the helper still works, keyed
# on physical cwd, with no git noise on stderr ---
NOGIT_DIR=$(mktemp -d)
NOGIT_STDERR="$FAKE_HOME/nogit.stderr"
NOGIT_OUT=$(cd "$NOGIT_DIR" && HOME="$FAKE_HOME" bash "$SCRIPT" --dir 2>"$NOGIT_STDERR")
if [ -n "$NOGIT_OUT" ] && [ ! -s "$NOGIT_STDERR" ]; then
  ok "works outside a git repo (physical-cwd fallback), no stderr noise"
else
  bad "expected a quiet physical-cwd fallback outside git, got stdout='$NOGIT_OUT' stderr='$(cat "$NOGIT_STDERR")'"
fi
trash "$NOGIT_DIR" 2>/dev/null || true

# --- a subdirectory of this repo resolves to the SAME project dir as the
# repo root (git-repo-root scoping, not raw cwd) ---
SUBDIR_OUT=$(cd "$ROOT/skills" && HOME="$FAKE_HOME" bash "$SCRIPT" --dir 2>/dev/null)
ROOT_OUT=$(cd "$ROOT" && HOME="$FAKE_HOME" bash "$SCRIPT" --dir 2>/dev/null)
if [ "$SUBDIR_OUT" = "$ROOT_OUT" ] && [ -n "$SUBDIR_OUT" ]; then
  ok "a subdirectory of the repo resolves to the same project dir as the repo root"
else
  bad "expected subdir and root to match, got '$SUBDIR_OUT' vs '$ROOT_OUT'"
fi

echo "handoff/handoff-path: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
