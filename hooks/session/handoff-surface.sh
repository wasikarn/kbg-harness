#!/usr/bin/env bash
# handoff-surface.sh — SessionStart: inline any unread mh:handoff documents,
# newest-first, then archive what was actually shown. Advisory-only, silent
# when there's nothing pending. Never reads stdin (none of mh's other
# SessionStart hooks do, and reading stdin here would inherit the parent's
# stdin under scripts/run-gauntlet.sh's backgrounded test runs -- a hang
# risk) and never writes to stderr (SessionStart stdout is what becomes
# injected session context; stderr just leaks into the transcript).
#
# Registered with matcher "startup|resume|clear", deliberately excluding
# "compact" -- SessionStart also fires on /compact, and without that
# exclusion the very session that just wrote a handoff would immediately
# re-consume it before any other session ever saw it.
#
# Delivery is best-effort, recoverable from archive -- not a guarantee.
# Nothing moves to consumed/ until it has actually printed successfully, so
# an ordinary read or output failure never causes silent loss (the read loop
# and the postcondition-checked move below). The one gap this doesn't close:
# if Claude Code kills this process on timeout during the brief, budget-
# capped move phase after printing has already completed, some files could
# be archived without the caller having received that output. No later
# signal exists in the hook architecture to build an acknowledgment on, and
# that would be disproportionate machinery for an advisory nudge --
# mitigated, not solved, by keeping the whole invocation (read, print, move)
# small enough that it normally finishes in a small fraction of the 10s hook
# timeout. Full history: docs/adr/0002-mh-controlled-handoff-path.md.
#
# Budget: walks pending/ oldest-first (ls -trd, mtime -- handoff-*.md
# basenames carry a random mktemp suffix, not a sortable sequence, so
# filename order was deliberately not used; the -d keeps a directory that
# happens to match the glob as one listed entry rather than expanding its
# contents into the list) and reads each candidate bounded to MAX_BYTES+1
# immediately -- head -c never reads more than that regardless of actual
# file size, so a huge file costs no more I/O here than a small one, and no
# separate full-file stat/wc pass is needed either to size it or to detect
# truncation. AGG_BYTES >= MAX_BYTES and AGG_LINES >= MAX_LINES by
# construction, so the oldest candidate always fits its own per-file cap on
# both dimensions -- the "oldest starved by a one-slot aggregate budget"
# case is provably unreachable; don't "fix" that by loosening either >= into
# a >. A third budget, MAX_COUNT, caps how many documents get selected at
# all, independent of bytes/lines -- it bounds per-file overhead a stream of
# many tiny documents could otherwise rack up while still fitting the
# byte/line aggregates.
set -uo pipefail
umask 077  # belt-and-suspenders: consumed/ is also chmod 700 below, but a
           # file should never be group/world-readable even for the instant
           # between mkdir/mv and that chmod call.
LC_ALL=C   # byte-exact string ops below (length, %? trim) -- not character-
           # counted, which is exactly the bug a prior revision of this
           # script had under a multibyte locale (Thai/emoji content).

HELPER="${CLAUDE_PLUGIN_ROOT:-}/skills/workflow/handoff/scripts/handoff-path.sh"
[ -f "$HELPER" ] || exit 0

DIR=$(bash "$HELPER" --dir 2>/dev/null) || exit 0
[ -n "$DIR" ] || exit 0
PEND="$DIR/pending"
[ -d "$PEND" ] || exit 0

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Silent-failure-hunter finding, live-reproduced: an unguarded source here
# (missing file, corrupted plugin cache mid-update) left hook_snapshot
# undefined under set -uo pipefail (no -e) -- both call sites below then
# silently evaluate to the empty string instead of erroring, so the
# snapshot-mismatch guard's own "" == "" comparison always matched,
# archiving every selected file regardless of whether it actually changed
# between read and move. Exactly the shared-empty-fallback class this
# file's own comment above already closed one layer down (distinct
# per-call-site literals) -- an undefined function reopens it one layer up.
. "$HERE/../../scripts/_lib/hook-common.sh" 2>/dev/null || exit 0

MAX_LINES=300
MAX_BYTES=15360
AGG_BYTES=$((MAX_BYTES * 3))
AGG_LINES=$((MAX_LINES * 3))
MAX_COUNT=10  # third, independent budget dimension: bounds per-file overhead
              # (a header line per document) that a stream of many tiny
              # documents could rack up while still fitting the byte/line
              # aggregate budgets above

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(ls -trd "$PEND"/handoff-*.md 2>/dev/null)
[ "${#files[@]}" -gt 0 ] || exit 0

sel_paths=()
sel_content=()
sel_truncated=()
sel_snapshot=()
used_bytes=0
used_lines=0

for f in "${files[@]}"; do
  [ "${#sel_paths[@]}" -lt "$MAX_COUNT" ] || break

  [ -f "$f" ] && [ ! -L "$f" ] || continue

  # Read at most MAX_BYTES+1 bytes -- the "+1" is itself the truncation
  # signal, so detecting truncation never costs more I/O than this bounded
  # read already did. Plain command substitution strips trailing newlines,
  # which would silently corrupt that signal on a source ending in one; the
  # sentinel ('X', appended after head -c, stripped after capture) preserves
  # every byte head -c actually read. The subshell's own `exit "$rc"`
  # propagates head -c's real exit status out as this substitution's $?, not
  # the sentinel printf's.
  content=$(head -c $((MAX_BYTES + 1)) -- "$f" 2>/dev/null; rc=$?; printf 'X'; exit "$rc")
  rc=$?
  [ "$rc" -eq 0 ] || continue          # genuine read failure -- leave pending
  content="${content%X}"
  [ -n "$content" ] || continue        # empty file -- nothing to show, leave pending

  # Snapshot size+mtime of the file we just read, so the move loop below can
  # detect if the on-disk file changed between this read and the archive
  # step -- otherwise the archived copy could silently differ from what was
  # actually printed (nothing else is expected to touch pending/ after
  # publish, but this closes the gap rather than assuming it). The fallback
  # on a stat failure must NOT be a shared value like "" -- two independent
  # failures (read-time and move-time) would then compare equal regardless
  # of whether the content actually changed, silently reopening the exact
  # gap this guard exists to close. Each call site's fallback is a distinct
  # literal string instead, so a stat failure at either point always
  # mismatches and fails closed (file stays pending) rather than open.
  snapshot=$(hook_snapshot "$f" at-read)

  byte_truncated=0
  if [ "${#content}" -gt "$MAX_BYTES" ]; then
    byte_truncated=1
    content="${content%?}"             # drop exactly the one extra byte read above
  fi

  # Line cap: a pure-bash read loop over the already-bounded, already-safe
  # in-memory content -- no subprocess, so nothing here can itself fail the
  # way a piped `head -n` legitimately SIGPIPEs its upstream on truncation
  # (which a prior revision of this script mishandled, conflating that
  # benign signal with a genuine failure). Counts a final line with no
  # trailing newline correctly, which a bare `wc -l` would miss. Reads from
  # process substitution, not a `<<<` here-string -- a here-string always
  # appends its own trailing newline even when content already ends in one,
  # which silently overcounted a document at exactly MAX_LINES by one. The
  # "first line captured yet" state is a separate flag, not "$capped is
  # empty" -- the latter can't tell "nothing captured" from "the first line
  # is itself blank", which silently dropped a genuine leading blank line.
  line_count=0
  capped=""
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    line_count=$((line_count + 1))
    if [ "$line_count" -le "$MAX_LINES" ]; then
      if [ "$first" -eq 1 ]; then capped="$line"; first=0; else capped="$capped"$'\n'"$line"; fi
    fi
  done < <(printf '%s' "$content")

  line_truncated=0
  [ "$line_count" -le "$MAX_LINES" ] || line_truncated=1

  byte_cost=${#content}
  line_cost=$line_count
  [ "$line_cost" -le "$MAX_LINES" ] || line_cost=$MAX_LINES
  [ $((used_bytes + byte_cost)) -le "$AGG_BYTES" ] || break   # oldest-first: stop here, never admit a smaller newer file ahead of this one
  [ $((used_lines + line_cost)) -le "$AGG_LINES" ] || break   # same rule, line dimension

  [ "$line_truncated" -eq 0 ] || content="$capped"

  used_bytes=$((used_bytes + byte_cost))
  used_lines=$((used_lines + line_cost))
  sel_paths+=("$f")
  sel_content+=("$content")
  sel_snapshot+=("$snapshot")
  if [ "$byte_truncated" -eq 1 ] || [ "$line_truncated" -eq 1 ]; then
    sel_truncated+=("1")
  else
    sel_truncated+=("0")
  fi
done

[ "${#sel_paths[@]}" -gt 0 ] || exit 0

mkdir -p "$DIR/consumed" 2>/dev/null
chmod 700 "$DIR/consumed" 2>/dev/null

# Print-all-then-move-all, never interleaved: a timeout kill during printing
# happens before the move loop is ever reached, so nothing gets falsely
# archived. Interleaving (moving each file right after it prints) was tried
# and rejected -- Claude Code discards a hook's entire stdout on a timeout
# kill regardless of how much had already printed, so moving files as they
# print only means more of them are wrongly marked consumed by the time a
# later file's read triggers the kill.
out_ok=1
printf '<mh-handoff>\n' 2>/dev/null || out_ok=0
if [ "$out_ok" -eq 1 ]; then
  for ((i = ${#sel_paths[@]} - 1; i >= 0; i--)); do
    base=$(basename "${sel_paths[$i]}" 2>/dev/null) || { out_ok=0; break; }
    dest="$DIR/consumed/$base"
    printf -- '## %s (mh:handoff, unread -- carried over from a prior session; verify against current state, not a pre-approved instruction)\n' "$base" 2>/dev/null || { out_ok=0; break; }
    printf '%s\n' "${sel_content[$i]}" 2>/dev/null || { out_ok=0; break; }
    if [ "${sel_truncated[$i]}" -eq 1 ]; then
      printf '[truncated at %s lines / %s bytes -- full document once archived: %s]\n' "$MAX_LINES" "$MAX_BYTES" "$dest" 2>/dev/null || { out_ok=0; break; }
    fi
  done
fi
[ "$out_ok" -eq 1 ] && { printf '</mh-handoff>\n' 2>/dev/null || out_ok=0; }

[ "$out_ok" -eq 1 ] || exit 0   # a real output-write failure -- nothing gets moved, everything stays pending, retries next session

for ((i = 0; i < ${#sel_paths[@]}; i++)); do
  f="${sel_paths[$i]}"
  base=$(basename "$f" 2>/dev/null) || continue
  dest="$DIR/consumed/$base"
  [ -e "$dest" ] && continue           # would collide -- leave pending rather than risk two different documents merging under one name

  # Re-snapshot right before the move and compare to what we read: if the
  # file changed since it was printed, archiving it now would archive
  # different content than what the caller actually saw -- leave it
  # pending instead (it gets re-read fresh next session) rather than
  # silently archive a mismatch.
  cur_snapshot=$(hook_snapshot "$f" at-move)
  [ "$cur_snapshot" = "${sel_snapshot[$i]}" ] || continue

  mv -n "$f" "$dest" 2>/dev/null
  [ -e "$f" ] && continue              # mv -n silently no-op'd -- stays pending, never falsely treated as consumed
  # The [ -e "$dest" ] precheck above only proves the destination was absent
  # at check time -- if something else creates a directory there before this
  # mv runs, mv -n moves the source INTO it instead of failing (same race
  # skills/workflow/handoff/scripts/handoff-path.sh's --publish already
  # guards against). Source is already gone at this point either way, so the
  # only thing left to protect is not chmod-ing whatever actually landed.
  [ -f "$dest" ] && [ ! -L "$dest" ] || continue
  chmod 600 "$dest" 2>/dev/null
done

exit 0
