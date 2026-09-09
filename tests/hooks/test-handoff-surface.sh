#!/usr/bin/env bash
# Unit tests for hooks/session/handoff-surface.sh — the SessionStart
# surfacer behind mh:handoff. Every non-obvious case here traces back to a
# specific Codex round-N finding from the plan review that shaped this
# script; see docs/adr/0002-mh-controlled-handoff-path.md for the full
# history. Run standalone: bash tests/hooks/test-handoff-surface.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/handoff-surface.sh"
HELPER="$ROOT/skills/workflow/handoff/scripts/handoff-path.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

FAKE_HOME=$(mktemp -d)
trap 'trash "$FAKE_HOME" "${EXTRA_TRASH[@]:-}" 2>/dev/null || true' EXIT
EXTRA_TRASH=()

# Every invocation below runs with CLAUDE_PLUGIN_ROOT pointed at this repo
# checkout (the real hooks/skills tree, not a fixture copy) so the hook
# finds the real helper -- only $HOME is faked, per project isolation.
export CLAUDE_PLUGIN_ROOT="$ROOT"

fresh_home() { local d; d=$(mktemp -d); EXTRA_TRASH+=("$d"); printf '%s' "$d"; }
alloc()   { HOME="$1" bash "$HELPER"; }
publish() { HOME="$1" bash "$HELPER" --publish "$2"; }
surface() { HOME="$1" bash "$HOOK"; }
# A published path is .../pending/<name>; its post-consumption location is
# .../consumed/<name> (the sibling dir), which is what to check AFTER
# running the hook -- checking the pending path itself after a successful
# run will always report "gone" since a successful consume IS the move.
consumed_path() { printf '%s' "$(dirname "$(dirname "$1")")/consumed/$(basename "$1")"; }

# --- no state dir at all: silent, exit 0 ---
H=$(fresh_home)
OUT=$(HOME="$H" bash "$HOOK" 2>"$H/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$H/err" ]; then
  ok "no state dir -- silent, exit 0"
else
  bad "expected silent exit 0 with no state dir, got rc=$rc stdout='$OUT' stderr='$(cat "$H/err")'"
fi

# --- state dir exists but pending/ is empty: silent ---
H=$(fresh_home)
mkdir -p "$(HOME="$H" bash "$HELPER" --dir)/pending"
OUT=$(HOME="$H" bash "$HOOK" 2>"$H/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$H/err" ]; then
  ok "empty pending/ -- silent, exit 0"
else
  bad "expected silent exit 0 on empty pending/, got rc=$rc stdout='$OUT' stderr='$(cat "$H/err")'"
fi

# --- one handoff: shown, moved to consumed/, then silent on rerun ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'Task: demo\nDone: wrote a test\n' > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if echo "$OUT" | grep -q 'Task: demo' && [ -f "$(consumed_path "$PUB")" ] && [ ! -e "$PUB" ] && [ ! -s "$H/err" ]; then
  ok "single handoff is inlined and moved to consumed/"
else
  bad "single-handoff happy path failed: out='$OUT' consumed_exists=$([ -f "$(consumed_path "$PUB")" ] && echo yes || echo no) still_pending=$([ -e "$PUB" ] && echo yes || echo no) stderr='$(cat "$H/err")'"
fi
OUT2=$(surface "$H" 2>"$H/err2")
if [ -z "$OUT2" ] && [ ! -s "$H/err2" ]; then
  ok "rerun after consumption is silent -- never auto-replayed"
else
  bad "expected silence on rerun, got '$OUT2' stderr='$(cat "$H/err2")'"
fi

# --- multiple pending: allocation is oldest-first, display is newest-first ---
H=$(fresh_home)
declare -a PUBS=()
for label in first second third; do
  P=$(alloc "$H"); printf 'label: %s\n' "$label" > "$P"
  PUBS+=("$(publish "$H" "$P")")
  sleep 1.1   # distinct mtimes for ls -tr ordering
done
OUT=$(surface "$H" 2>"$H/err")
THIRD_LN=$(echo "$OUT" | grep -n 'label: third' | cut -d: -f1)
FIRST_LN=$(echo "$OUT" | grep -n 'label: first' | cut -d: -f1)
if [ -n "$THIRD_LN" ] && [ -n "$FIRST_LN" ] && [ "$THIRD_LN" -lt "$FIRST_LN" ]; then
  ok "three pending: newest (third) prints before oldest (first)"
else
  bad "expected newest-first display order, got: $OUT"
fi
ALL_MOVED=1
for p in "${PUBS[@]}"; do [ -f "$(consumed_path "$p")" ] && [ ! -e "$p" ] || ALL_MOVED=0; done
if [ "$ALL_MOVED" -eq 1 ] && [ ! -s "$H/err" ]; then
  ok "all three small pending files are consumed in one pass"
else
  bad "expected all three consumed"
fi

# --- Codex round 2/5: oversized file is truncated at MAX_BYTES, shown, and
# STILL consumed (per-file truncation means shown, not held back) ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "print('x' * 20000, end='')" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if echo "$OUT" | grep -q 'truncated at 300 lines / 15360 bytes' && [ -f "$(consumed_path "$PUB")" ] && [ ! -e "$PUB" ] && [ ! -s "$H/err" ]; then
  ok "oversized file: truncated, shown, and still consumed"
else
  bad "oversized-file truncation/consumption failed: $(echo "$OUT" | tail -c 200) consumed_exists=$([ -f "$(consumed_path "$PUB")" ] && echo yes || echo no)"
fi

# --- Codex round 5, P2, reproduced live: a source whose (MAX_BYTES+1)-th
# byte is a trailing newline must still be detected as truncated. Plain
# $() command substitution silently strips trailing newlines, which broke
# the exact-length truncation check on a prior revision. ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "import sys; sys.stdout.write('a'*15359 + chr(10) + 'TAIL')" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if echo "$OUT" | grep -q 'truncated at' && ! echo "$OUT" | grep -q 'TAIL' && [ -f "$(consumed_path "$PUB")" ]; then
  ok "truncation detected when the byte just past the cap is a trailing newline (Codex round 5 repro)"
else
  bad "trailing-newline truncation not detected: $(echo "$OUT" | tail -c 200)"
fi

# --- multiple trailing newlines, and a final line with NO trailing newline,
# both count correctly toward the line cap (a bare wc -l undercounts the
# latter) ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "
import sys
for i in range(302):
    sys.stdout.write('line %d\n' % i)
sys.stdout.write('final line no newline')
" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if echo "$OUT" | grep -q 'truncated at 300 lines' && echo "$OUT" | grep -q 'line 299' && ! echo "$OUT" | grep -q 'line 300'; then
  ok "line cap includes a final line with no trailing newline in its count, truncates at exactly 300"
else
  bad "line-count-with-no-final-newline case failed: $(echo "$OUT" | tail -c 300)"
fi

# --- Codex round 1: symlink to a real file must never be inlined, even
# live (not just dangling), and is left untouched in pending/ ---
H=$(fresh_home)
PEND=$(HOME="$H" bash "$HELPER" --dir)/pending
mkdir -p "$PEND"
SECRET=$(mktemp); EXTRA_TRASH+=("$SECRET")
printf 'SECRET_DO_NOT_LEAK\n' > "$SECRET"
LIVE_LINK="$PEND/handoff-19700101T000000.livelink.md"
ln -s "$SECRET" "$LIVE_LINK"
DANGLING_LINK="$PEND/handoff-19700101T000001.dangling.md"
ln -s "/nonexistent/nowhere" "$DANGLING_LINK"
mkdir -p "$PEND/handoff-19700101T000002.subdir.md"   # a directory, not a file
printf 'not a handoff\n' > "$PEND/notes.md.bak"       # doesn't match handoff-*.md at all
OUT=$(surface "$H" 2>"$H/err")
if ! echo "$OUT" | grep -q SECRET_DO_NOT_LEAK && [ -L "$LIVE_LINK" ] && [ -L "$DANGLING_LINK" ] && [ -d "$PEND/handoff-19700101T000002.subdir.md" ]; then
  ok "live symlink, dangling symlink, a directory, and a non-matching file are all ignored, none inlined or moved"
else
  bad "junk-in-pending/ handling failed: out='$OUT'"
fi

# --- empty file: skipped, stays pending, no crash ---
H=$(fresh_home)
P=$(alloc "$H"); : > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if [ -z "$OUT" ] && [ -f "$PUB" ] && [ ! -s "$H/err" ]; then
  ok "empty published file is skipped, stays pending, hook exits quietly"
else
  bad "empty-file handling failed: out='$OUT' pub_exists=$([ -f "$PUB" ] && echo yes || echo no)"
fi

# --- Codex round 3, P1: a single pathological 1MB line (no newlines) is
# memory-bounded by the byte-first read and truncates correctly, quickly ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "print('x' * 1000000, end='')" > "$P"
PUB=$(publish "$H" "$P")
START=$(date +%s)
OUT=$(surface "$H" 2>"$H/err")
ELAPSED=$(( $(date +%s) - START ))
if echo "$OUT" | grep -q 'truncated at' && [ -f "$(consumed_path "$PUB")" ] && [ "$ELAPSED" -lt 5 ]; then
  ok "a 1MB single-line file truncates correctly and completes quickly (memory-bounded, not buffered whole)"
else
  bad "pathological-long-line case failed or was slow (${ELAPSED}s), output length ${#OUT} chars"
fi

# --- Codex round 3, P1: multibyte UTF-8 (Thai) content truncates on an
# exact byte boundary -- not a character-count slice, which previously
# mis-truncated at 3x the intended byte length ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "import sys; sys.stdout.write('ก' * 20000)" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
printf '%s' "$OUT" > "$H/out.bin"
BODY_BYTES=$(python3 -c "
data = open('$H/out.bin', 'rb').read()
start = data.index(b'unread -- carried')
body_start = data.index(b'\n', start) + 1
body_end = data.index(b'\n[truncated', body_start)
print(body_end - body_start)
" 2>/dev/null)
if [ "$BODY_BYTES" = "15360" ]; then
  ok "multibyte UTF-8 content truncates at exactly MAX_BYTES (15360), byte-exact"
else
  bad "expected truncated body of exactly 15360 bytes, got $BODY_BYTES"
fi

# --- Codex round 2, P1: genuine read failure (fault-injected) leaves the
# file in pending/, distinct from the truncation case above which consumes ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'will be unreadable\n' > "$P"
PUB=$(publish "$H" "$P")
chmod 000 "$PUB"
OUT=$(surface "$H" 2>"$H/err")
RESULT_OK=0
if [ -z "$OUT" ] && [ -f "$PUB" ] && [ ! -s "$H/err" ]; then RESULT_OK=1; fi
chmod 600 "$PUB"
if [ "$RESULT_OK" -eq 1 ]; then
  ok "genuine read failure (permission denied) leaves the file pending, unprinted, silent"
else
  bad "expected silent pending-retry on a genuine read failure"
fi

# --- Codex round 4, P1: an output-write failure (distinct from a read
# failure) also leaves every file pending, not consumed. Closing stdout
# before the hook runs turns every printf into a real, non-signal EBADF
# failure this test can observe (a broken-pipe/SIGPIPE would instead just
# kill the process outright, which is the already-accepted, separately
# documented timeout-kill gap -- this exercises the OTHER path: a write
# that fails without terminating the script). ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'must not be lost on an output failure\n' > "$P"
PUB=$(publish "$H" "$P")
HOME="$H" bash "$HOOK" >&- 2>"$H/err_outfail"
if [ -f "$PUB" ]; then
  ok "an output-write failure (stdout closed) leaves the file pending, not falsely consumed"
else
  bad "file was consumed despite the output write having failed"
fi

# --- Codex round 3, P2: a destination collision on the consume side
# (contrived by pre-placing a document at the exact name the hook would
# move to) is refused, not silently accepted via mv -n's exit 0 ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'new content\n' > "$P"
PUB=$(publish "$H" "$P")
CONS_DIR="$(dirname "$(dirname "$PUB")")/consumed"
mkdir -p "$CONS_DIR"
COLLIDE_DEST="$CONS_DIR/$(basename "$PUB")"
printf 'pre-existing archived document, must survive untouched\n' > "$COLLIDE_DEST"
OUT=$(surface "$H" 2>"$H/err")
if [ "$(cat "$COLLIDE_DEST")" = "pre-existing archived document, must survive untouched" ] && [ -f "$PUB" ]; then
  ok "a consume-side destination collision leaves the pre-existing archive untouched and the pending copy in place"
else
  bad "consume-side collision handling corrupted state"
fi

# --- directory/file mode is 0700/0600 at the consumed/ write point ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'perm check\n' > "$P"
PUB=$(publish "$H" "$P")
surface "$H" >/dev/null 2>&1
CONS_DIR="$(dirname "$(dirname "$PUB")")/consumed"
DIR_MODE=$(stat -f '%Lp' "$CONS_DIR" 2>/dev/null || stat -c '%a' "$CONS_DIR" 2>/dev/null)
FILE_MODE=$(stat -f '%Lp' "$CONS_DIR/$(basename "$PUB")" 2>/dev/null || stat -c '%a' "$CONS_DIR/$(basename "$PUB")" 2>/dev/null)
if [ "$DIR_MODE" = "700" ] && [ "$FILE_MODE" = "600" ]; then
  ok "consumed/ is 0700, the archived file is 0600"
else
  bad "expected consumed/ 700 and file 600, got dir=$DIR_MODE file=$FILE_MODE"
fi

# --- missing helper: silent, exit 0 ---
H=$(fresh_home)
BOGUS_ROOT=$(mktemp -d); EXTRA_TRASH+=("$BOGUS_ROOT")
OUT=$(HOME="$H" CLAUDE_PLUGIN_ROOT="$BOGUS_ROOT" bash "$HOOK" 2>"$H/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$H/err" ]; then
  ok "missing helper (bogus CLAUDE_PLUGIN_ROOT) -- silent, exit 0"
else
  bad "expected silent exit 0 with a missing helper, got rc=$rc stdout='$OUT' stderr='$(cat "$H/err")'"
fi

# --- CLAUDE_PLUGIN_ROOT entirely unset: silent, exit 0 ---
H=$(fresh_home)
OUT=$(HOME="$H" env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>"$H/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ ! -s "$H/err" ]; then
  ok "CLAUDE_PLUGIN_ROOT unset -- silent, exit 0"
else
  bad "expected silent exit 0 with CLAUDE_PLUGIN_ROOT unset, got rc=$rc stdout='$OUT' stderr='$(cat "$H/err")'"
fi

# --- the registered hooks.json entry excludes "compact" from its matcher
# (Codex round 1: without this, /compact in the very session that just
# wrote a handoff would immediately re-consume it). This is a config
# property, not something the script itself can be driven to prove, since
# the script never reads the SessionStart "source" field at all. ---
MATCHER=$(python3 -c "
import json
with open('$ROOT/hooks/hooks.json') as f:
    data = json.load(f)
for entry in data['hooks'].get('SessionStart', []):
    if entry.get('id') == 'session:handoff-surface':
        print(entry.get('matcher', ''))
        break
")
if [ "$MATCHER" = "startup|resume|clear" ]; then
  ok "hooks.json matcher is startup|resume|clear, excluding compact"
else
  bad "expected matcher 'startup|resume|clear', got '$MATCHER'"
fi

# --- compliance-audit finding: a here-string (<<<) always appends its own
# trailing newline even when the content already ends in one, which
# silently overcounted a document at exactly MAX_LINES (300) by one and
# falsely flagged it truncated. A document with exactly 300 properly
# newline-terminated lines must NOT be reported truncated. ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "
for i in range(300):
    print('exactline %d' % i)
" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
if ! echo "$OUT" | grep -q 'truncated at' && echo "$OUT" | grep -q 'exactline 299' && [ -f "$(consumed_path "$PUB")" ]; then
  ok "a document with exactly 300 newline-terminated lines is not falsely flagged truncated"
else
  bad "exact-300-line document was falsely truncated: $(echo "$OUT" | tail -c 200)"
fi

# --- compliance-audit finding: the "first line captured yet" state used to
# be "$capped is empty", which can't tell "nothing captured" from "the
# first line is itself blank" -- a genuine leading blank line was silently
# dropped and every following line shifted up with no separator. ---
H=$(fresh_home)
P=$(alloc "$H"); python3 -c "
print('')
for i in range(400):
    print('blankline %d' % i)
" > "$P"
PUB=$(publish "$H" "$P")
OUT=$(surface "$H" 2>"$H/err")
FIRSTBODY=$(echo "$OUT" | grep -A1 'mh:handoff, unread' | tail -n1)
if [ -z "$FIRSTBODY" ] && echo "$OUT" | grep -q 'blankline 298' && ! echo "$OUT" | grep -q 'blankline 299'; then
  ok "a genuine leading blank line survives truncation instead of being silently dropped"
else
  bad "leading blank line was lost: first body line was '$FIRSTBODY'"
fi

# --- compliance-audit finding: there was no aggregate LINE budget, only an
# aggregate BYTE budget -- four small documents (well under the byte
# budget) at exactly 300 lines each total 1200 lines, over the 900-line
# aggregate cap (3x per-file). The three oldest must be shown and consumed;
# the newest must stay pending, same oldest-first fairness as the byte
# budget already has. ---
H=$(fresh_home)
declare -a AGGPUBS=()
for label in aggA aggB aggC aggD; do
  P=$(alloc "$H")
  python3 -c "
for i in range(300):
    print('$label line %d' % i)
" > "$P"
  AGGPUBS+=("$(publish "$H" "$P")")
  sleep 1.1
done
OUT=$(surface "$H" 2>"$H/err")
if echo "$OUT" | grep -q 'aggA line 0' && echo "$OUT" | grep -q 'aggB line 0' && echo "$OUT" | grep -q 'aggC line 0' \
  && ! echo "$OUT" | grep -q 'aggD line 0' \
  && [ -f "$(consumed_path "${AGGPUBS[0]}")" ] && [ -f "$(consumed_path "${AGGPUBS[1]}")" ] && [ -f "$(consumed_path "${AGGPUBS[2]}")" ] \
  && [ -f "${AGGPUBS[3]}" ] && [ ! -s "$H/err" ]; then
  ok "aggregate line budget (900 = 3x300) admits the three oldest 300-line documents and leaves the newest pending"
else
  bad "aggregate line budget not enforced: $(echo "$OUT" | tail -c 300)"
fi

# --- compliance-audit finding, live-reproduced: ls -tr on a directory that
# matches the handoff-*.md glob (no -d) expands into that directory's own
# children as BARE basenames -- the loop then resolves those bare names
# relative to the hook's own cwd, not pending/, and can read + move an
# unrelated file that happens to share a name there. Uses a throwaway git
# repo as cwd (never the real matt-harness tree) so the project dir the
# hook resolves matches where the fixture was planted. ---
FIXTURE_REPO=$(mktemp -d); EXTRA_TRASH+=("$FIXTURE_REPO")
(cd "$FIXTURE_REPO" && git init -q -b main >/dev/null 2>&1)
H=$(fresh_home)
PEND=$(cd "$FIXTURE_REPO" && HOME="$H" bash "$HELPER" --dir)/pending
mkdir -p "$PEND"
DIRMATCH="$PEND/handoff-19700101T000003.dirmatch.md"
mkdir -p "$DIRMATCH"
printf 'irrelevant\n' > "$DIRMATCH/decoy.md"
printf 'CWD_OUTSIDE_SENTINEL\n' > "$FIXTURE_REPO/decoy.md"
OUT=$(cd "$FIXTURE_REPO" && HOME="$H" bash "$HOOK" 2>"$H/err")
if ! echo "$OUT" | grep -q CWD_OUTSIDE_SENTINEL && [ -f "$FIXTURE_REPO/decoy.md" ] && [ -d "$DIRMATCH" ] && [ ! -s "$H/err" ]; then
  ok "a directory matching the pending glob never leaks its children's bare names into cwd-relative file resolution"
else
  bad "directory-glob enumeration leaked into cwd: out='$OUT' decoy_survived=$([ -f "$FIXTURE_REPO/decoy.md" ] && echo yes || echo no)"
fi

# --- compliance-audit finding: content was read into memory once (for
# printing) but the archive step later mv's whatever is on disk at that
# later point -- if the file changed in between, the archived copy could
# differ from what was actually printed. A stat shim simulates that change
# by returning a different size/mtime snapshot on the second call (the
# move-time recheck) than the first (the read-time snapshot); the file
# must be printed (already captured in memory) but left pending, not
# archived, on a mismatch. ---
H=$(fresh_home)
P=$(alloc "$H"); printf 'content that must not be archived if it appears to change mid-run\n' > "$P"
PUB=$(publish "$H" "$P")
STAT_SHIM_DIR=$(mktemp -d); EXTRA_TRASH+=("$STAT_SHIM_DIR")
STAT_COUNTER=$(mktemp); EXTRA_TRASH+=("$STAT_COUNTER")
printf '0' > "$STAT_COUNTER"
cat > "$STAT_SHIM_DIR/stat" <<EOF
#!/usr/bin/env bash
n=\$(cat "$STAT_COUNTER")
n=\$((n + 1))
printf '%s' "\$n" > "$STAT_COUNTER"
if [ "\$n" -le 1 ]; then printf '111 1111111111\n'; else printf '222 2222222222\n'; fi
EOF
chmod +x "$STAT_SHIM_DIR/stat"
OUT=$(HOME="$H" PATH="$STAT_SHIM_DIR:$PATH" bash "$HOOK" 2>"$H/err")
if echo "$OUT" | grep -q 'content that must not be archived' && [ -f "$PUB" ] && [ ! -s "$H/err" ]; then
  ok "a file whose snapshot differs between read and move is printed from memory but left pending, never archived on a mismatch"
else
  bad "snapshot-mismatch guard failed: out='$OUT' pub_exists=$([ -f "$PUB" ] && echo yes || echo no)"
fi

echo "hooks/handoff-surface: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
