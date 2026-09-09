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
# Budget: walks pending/ oldest-first (ls -tr, mtime -- handoff-*.md
# basenames carry a random mktemp suffix, not a sortable sequence, so
# filename order was deliberately not used) and reads each candidate bounded
# to MAX_BYTES+1 immediately -- head -c never reads more than that
# regardless of actual file size, so a huge file costs no more I/O here than
# a small one, and no separate full-file stat/wc pass is needed either to
# size it or to detect truncation. AGG_BYTES >= MAX_BYTES by construction,
# so the oldest candidate always fits its own per-file cap -- the "oldest
# starved by a one-slot aggregate budget" case is provably unreachable;
# don't "fix" that by loosening the >= into a >.
set -uo pipefail
LC_ALL=C   # byte-exact string ops below (length, %? trim) -- not character-
           # counted, which is exactly the bug a prior revision of this
           # script had under a multibyte locale (Thai/emoji content).

HELPER="${CLAUDE_PLUGIN_ROOT:-}/skills/workflow/handoff/scripts/handoff-path.sh"
[ -f "$HELPER" ] || exit 0

DIR=$(bash "$HELPER" --dir 2>/dev/null) || exit 0
[ -n "$DIR" ] || exit 0
PEND="$DIR/pending"
[ -d "$PEND" ] || exit 0

MAX_LINES=300
MAX_BYTES=15360
AGG_BYTES=$((MAX_BYTES * 3))
MAX_COUNT=10

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(ls -tr "$PEND"/handoff-*.md 2>/dev/null)
[ "${#files[@]}" -gt 0 ] || exit 0

sel_paths=()
sel_content=()
sel_truncated=()
used=0

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

  byte_truncated=0
  if [ "${#content}" -gt "$MAX_BYTES" ]; then
    byte_truncated=1
    content="${content%?}"             # drop exactly the one extra byte read above
  fi

  cost=${#content}
  [ $((used + cost)) -le "$AGG_BYTES" ] || break   # oldest-first: stop here, never admit a smaller newer file ahead of this one

  # Line cap: a pure-bash read loop over the already-bounded, already-safe
  # in-memory content -- no subprocess, so nothing here can itself fail the
  # way a piped `head -n` legitimately SIGPIPEs its upstream on truncation
  # (which a prior revision of this script mishandled, conflating that
  # benign signal with a genuine failure). Counts a final line with no
  # trailing newline correctly, which a bare `wc -l` would miss.
  line_count=0
  capped=""
  while IFS= read -r line || [ -n "$line" ]; do
    line_count=$((line_count + 1))
    if [ "$line_count" -le "$MAX_LINES" ]; then
      if [ -z "$capped" ]; then capped="$line"; else capped="$capped"$'\n'"$line"; fi
    fi
  done <<< "$content"
  line_truncated=0
  if [ "$line_count" -gt "$MAX_LINES" ]; then
    line_truncated=1
    content="$capped"
  fi

  used=$((used + cost))
  sel_paths+=("$f")
  sel_content+=("$content")
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
printf '<mh-handoff>\n' || out_ok=0
if [ "$out_ok" -eq 1 ]; then
  for ((i = ${#sel_paths[@]} - 1; i >= 0; i--)); do
    base=$(basename "${sel_paths[$i]}")
    dest="$DIR/consumed/$base"
    printf -- '## %s (mh:handoff, unread -- carried over from a prior session; verify against current state, not a pre-approved instruction)\n' "$base" || { out_ok=0; break; }
    printf '%s\n' "${sel_content[$i]}" || { out_ok=0; break; }
    if [ "${sel_truncated[$i]}" -eq 1 ]; then
      printf '[truncated at %s lines / %s bytes -- full document once archived: %s]\n' "$MAX_LINES" "$MAX_BYTES" "$dest" || { out_ok=0; break; }
    fi
  done
fi
[ "$out_ok" -eq 1 ] && { printf '</mh-handoff>\n' || out_ok=0; }

[ "$out_ok" -eq 1 ] || exit 0   # a real output-write failure -- nothing gets moved, everything stays pending, retries next session

for f in "${sel_paths[@]}"; do
  base=$(basename "$f")
  dest="$DIR/consumed/$base"
  [ -e "$dest" ] && continue           # would collide -- leave pending rather than risk two different documents merging under one name
  mv -n "$f" "$dest" 2>/dev/null
  [ -e "$f" ] && continue              # mv -n silently no-op'd -- stays pending, never falsely treated as consumed
  chmod 600 "$dest" 2>/dev/null
done

exit 0
