#!/usr/bin/env bash
# fragments-state.sh — sourceable lib shared by hooks/sensors/fragments-arm.sh,
# hooks/sensors/fragments-capture.sh, and hooks/session/fragments-surface.sh,
# so the state layout, sanitizer, and lock discipline can't drift apart
# between the three hooks. Not a CLI like skills/workflow/handoff/scripts/
# handoff-path.sh -- source it, don't execute it.
#
# Storage: $HOME/.claude/state/mh-fragments/<slug>-<hash>/documents/
#          <sha256(path)[:16]>.json
# <slug>-<hash> from slug_hash() (scripts/_lib/slug-hash.sh), scoped to the
# git repo root -- identical derivation to handoff-path.sh and
# codex-state-path.sh, so two different repos never collide.
#
# The durable state tree gets the same symlink+ownership defense the
# ephemeral TMPDIR arm marker needs (docs/adr/0003-writing-fragments-
# pointer-capture.md, round-1 finding) -- every directory in the chain is
# checked, not just the base.

_FRAGMENTS_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_FRAGMENTS_LIB_DIR/slug-hash.sh"

# _fragments_owner_ok <path>: true iff <path>'s owner uid matches ours.
# Fails closed on any stat/id failure.
_fragments_owner_ok() {
  local path="$1" uid
  uid=$(stat -f '%u' "$path" 2>/dev/null || stat -c '%u' "$path" 2>/dev/null) || return 1
  [ "$uid" = "$(id -u 2>/dev/null)" ]
}

# _fragments_safe_dir <path>: mkdir -p, then reject if it's a symlink or
# foreign-owned. <path> must carry no trailing slash -- a trailing slash
# resolves through a symlink before -L ever runs, silently defeating the
# check (hooks/session/handoff-nudge.sh's own compliance-audit finding,
# reproduced live there).
_fragments_safe_dir() {
  local path="$1"
  mkdir -p "$path" 2>/dev/null
  [ -d "$path" ] || return 1
  [ ! -L "$path" ] || return 1
  _fragments_owner_ok "$path" || return 1
  chmod 700 "$path" 2>/dev/null
  return 0
}

# fragments_state_dir <root>: this project's mh-fragments dir
# ($HOME/.claude/state/mh-fragments/<slug>-<hash>), ensuring every level of
# the chain exists and passes the symlink/ownership check. Prints nothing
# and returns 1 on any failure (no sha256 tool, root doesn't exist, a
# hijacked directory anywhere in the chain).
fragments_state_dir() {
  local root="$1" slughash base proj
  slughash=$(slug_hash "$root") || return 1
  base="$HOME/.claude/state/mh-fragments"
  _fragments_safe_dir "$base" || return 1
  proj="$base/$slughash"
  _fragments_safe_dir "$proj" || return 1
  printf '%s\n' "$proj"
}

# fragments_docs_dir <root>: <project-dir>/documents, same chain-of-checks
# discipline as fragments_state_dir.
fragments_docs_dir() {
  local root="$1" proj docs
  proj=$(fragments_state_dir "$root") || return 1
  docs="$proj/documents"
  _fragments_safe_dir "$docs" || return 1
  printf '%s\n' "$docs"
}

# fragments_snapshot <path>: size+mtime, portable (BSD vs GNU stat), same
# derivation as handoff-surface.sh's own snapshot guard. Each failure path
# is a DISTINCT literal -- two independent stat failures must never compare
# equal (handoff-surface.sh's own deep-audit finding: a shared "" fallback
# let a missing `stat` binary fail the guard open).
fragments_snapshot() {
  local path="$1" who="${2:-x}"
  stat -f '%z %m' "$path" 2>/dev/null || stat -c '%s %Y' "$path" 2>/dev/null || printf 'stat-unavailable-%s\n' "$who"
}

# fragments_sanitize <value> <label> [maxlen]: redacts the ENTIRE value
# (never a partial escape) if it contains any control character or a
# literal '<' or '>'. Applied identically to both the path and the title at
# every place either is printed (hook 1's known-path injection, hook 3's
# surface block) -- defined once here so the two call sites can't drift
# apart. Only NUL and '/' are actually forbidden in a path component, so a
# path can legitimately contain a literal newline and injection-shaped text
# simultaneously -- it gets the exact same treatment as the title, not a
# lighter one. A clean value is still truncated to maxlen (0 = no limit).
fragments_sanitize() {
  local value="$1" label="$2" maxlen="${3:-0}"
  python3 -c '
import re, sys
value, label, maxlen = sys.argv[1], sys.argv[2], int(sys.argv[3])
if re.search(r"[\x00-\x1f\x7f<>]", value):
    print("[" + label + " redacted -- contains control/markup characters]")
else:
    if maxlen > 0 and len(value) > maxlen:
        value = value[:maxlen] + "..."
    print(value)
' "$value" "$label" "$maxlen" 2>/dev/null
}

# fragments_lock_acquire <lock-dir>: bounded-retry mkdir-based lock -- the
# same atomic test-and-set primitive the claim step in fragments-capture.sh
# already relies on, not a new dependency (flock isn't reliably portable
# across this repo's target shells). Contention is expected only between
# fragments-arm.sh's pointer publish and fragments-surface.sh's stale-
# pointer removal, both very short critical sections, so this budget is
# generous, not tight. Prints nothing; returns 0 on success, 1 if still
# held after the retry budget -- callers must have a defined behavior for
# both outcomes (see docs/adr/0003-... "Pointer publish/sweep lock").
fragments_lock_acquire() {
  local dir="$1" attempts_left=5
  while [ "$attempts_left" -gt 0 ]; do
    mkdir "$dir" 2>/dev/null && return 0
    sleep 0.04
    attempts_left=$((attempts_left - 1))
  done
  return 1
}

fragments_lock_release() {
  rmdir "$1" 2>/dev/null
  return 0
}
