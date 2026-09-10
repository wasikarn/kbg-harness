#!/usr/bin/env bash
# harness.sh — shared test scaffolding for tests/hooks/test-fragments-{arm,
# capture,surface}.sh and tests/hooks/test-handoff-{nudge,surface}.sh: the
# fresh_tmpdir/fresh_repo/_cleanup_trash trio that used to be 5 separate
# copies, 3 of which were missing the empty-string guard the other 2 had --
# the exact bug that moved this repo's working tree to Trash mid-session
# (trash "" deletes the process's cwd). One definition so that guard can't
# be present in some copies and missing in others again.
#
# Not matched by any of scripts/run-gauntlet.sh's five test-discovery globs
# (tests/hooks/*.sh, tests/skills/test*.sh, tests/skills/*/test*.sh,
# tests/scripts/test*.sh, tests/evals/test*.sh) -- this lives under
# tests/_lib/, so it is linted (git ls-files '*.sh') but never executed as
# a test itself. Source it, don't execute it.
#
# Caller contract: this file declares EXTRA_TRASH and the functions below;
# it never registers the EXIT trap itself, so each caller still does its
# own `trap _cleanup_trash EXIT` after sourcing.

EXTRA_TRASH=()

# track_trash <path>: register <path> for cleanup at _cleanup_trash time.
# Filters empty unconditionally -- the same guard fresh_tmpdir applies,
# available separately for a caller's own mktemp/mkdir calls that don't go
# through fresh_tmpdir (a single mktemp file, a manually-named dir).
track_trash() {
  [ -n "${1:-}" ] && EXTRA_TRASH+=("$1")
  return 0
}

# fresh_tmpdir: mktemp -d, tracked for cleanup. Prints the path.
fresh_tmpdir() {
  local d
  d=$(mktemp -d)
  track_trash "$d"
  printf '%s' "$d"
}

# fresh_repo: fresh_tmpdir, git-initialized. Prints the path.
fresh_repo() {
  local d
  d=$(fresh_tmpdir)
  (cd "$d" && git init -q && git config user.email t@t.com && git config user.name t) >/dev/null 2>&1
  printf '%s' "$d"
}

# _cleanup_trash: the EXIT trap body. Every target -- $FAKE_HOME (if the
# caller set it) plus every tracked EXTRA_TRASH entry -- is filtered to
# non-empty before trash ever sees it: `trash ""` deletes the process's
# current working directory, confirmed live (this repo's working tree was
# moved to Trash mid-session by exactly this bug, in a copy of this
# function that lacked the filter).
_cleanup_trash() {
  local t targets=()
  [ -n "${FAKE_HOME:-}" ] && targets+=("$FAKE_HOME")
  for t in "${EXTRA_TRASH[@]:-}"; do
    [ -n "$t" ] && targets+=("$t")
  done
  [ "${#targets[@]}" -eq 0 ] || trash "${targets[@]}" 2>/dev/null
  return 0
}
