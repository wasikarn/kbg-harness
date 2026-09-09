#!/usr/bin/env bash
# handoff-path.sh — compute this project's mh-handoff paths, or publish a
# staged document into pending/.
#
# Storage: $HOME/.claude/state/mh-handoffs/<slug>-<hash>/{staging,pending,consumed}/
# Scoped to git repo root (falls back to physical cwd outside a repo) so a
# handoff written from a subdirectory still surfaces from anywhere in the
# same repo, and two different repos never collide. <slug>-<hash> is
# scripts/_lib/slug-hash.sh's derivation, shared with
# scripts/_lib/codex-state-path.sh: basename sanitized to [a-zA-Z0-9._-],
# plus the first 16 hex chars of sha256(realpath) for collision-freedom (a
# bare slug alone can collide -- two repos both named "app" on different
# disks, or .../a-b vs .../a/b under a naive "/" -> "-").
#
# Default (no args): mkdir -p's staging/ (0700), atomically reserves a name
# via mktemp, prints the staging path. Nothing is published yet -- the
# surfacer hook never sees this file until --publish moves it. The template
# ends in a literal, trailing XXXXXX with nothing after it: BSD/macOS mktemp
# only randomizes a *trailing* run of X's, so anything after them (a design
# this script went through once and rejected) creates a literally unrandomized
# name and collides on the second call.
#
# --publish <staging-path>: validates the path is inside this project's
# staging/ dir and is a plain regular file (never a symlink), then mv -n's it
# into pending/ (0600), prints the published path. mv -n exits 0 even when it
# silently refuses to overwrite an existing destination, so success is
# verified by postcondition (source actually gone), never by mv's exit code
# alone. Fails loud (stderr + exit 1) on any failure.
#
# --dir: prints the project's mh-handoff directory only. Creates nothing --
# used by the SessionStart surfacer, which must stay silent (never create an
# empty state dir machine-wide) when a project has never run /mh:handoff.
set -uo pipefail
umask 077  # belt-and-suspenders: every dir/file below is also chmod'd
           # explicitly to 0700/0600, but this closes the window between
           # mkdir/mktemp/mv and that chmod call, and the chmod checks below
           # still fail loud if the filesystem rejects it outright.

fail() { echo "handoff-path: $1" >&2; exit 1; }

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../../../scripts/_lib/slug-hash.sh"

# Project root: git repo root, falling back to physical cwd outside a repo.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd -P)"
[ -n "$ROOT" ] || fail "could not determine a project root"

SLUGHASH=$(slug_hash "$ROOT") || fail "no sha256 tool available (shasum or sha256sum)"

PROJECT_DIR="$HOME/.claude/state/mh-handoffs/$SLUGHASH"

case "${1:-}" in
  --dir)
    printf '%s\n' "$PROJECT_DIR"
    exit 0
    ;;
  --publish)
    STAGED="${2:-}"
    [ -n "$STAGED" ] || fail "--publish requires a staging path"
    STAGING_DIR="$PROJECT_DIR/staging"

    STAGED_PARENT=$(cd -P "$(dirname "$STAGED")" 2>/dev/null && pwd) || fail "staging path's directory does not exist: $STAGED"
    STAGED_REAL="$STAGED_PARENT/$(basename "$STAGED")"

    # Canonicalize STAGING_DIR the same way before comparing -- on macOS the
    # $HOME a test fixture uses (mktemp -d, under $TMPDIR's /var/folders/...)
    # is itself a symlink into /private/var/folders/...; STAGED_REAL above is
    # already resolved through it via cd -P, so an unresolved STAGING_DIR
    # would never match even for a legitimately-staged path.
    STAGING_DIR_REAL=$(cd -P "$STAGING_DIR" 2>/dev/null && pwd) || fail "this project's staging dir does not exist yet: $STAGING_DIR"
    case "$STAGED_REAL" in
      "$STAGING_DIR_REAL"/*) : ;;
      *) fail "refusing to publish a path outside this project's staging dir: $STAGED" ;;
    esac
    [ -f "$STAGED_REAL" ] || fail "staging path is not a regular file: $STAGED"
    [ ! -L "$STAGED_REAL" ] || fail "refusing to publish a symlink: $STAGED"

    BASE_NAME=$(basename "$STAGED_REAL")
    # .handoff-<ts>.XXXXXX -> handoff-<ts>.XXXXXX.md (strip leading dot, add .md)
    PUB_NAME="${BASE_NAME#.}.md"
    PENDING_DIR="$PROJECT_DIR/pending"
    mkdir -p "$PENDING_DIR" 2>/dev/null || fail "could not create $PENDING_DIR"
    chmod 700 "$PROJECT_DIR" "$PENDING_DIR" 2>/dev/null || fail "could not set permissions (0700) on $PROJECT_DIR or $PENDING_DIR"

    DEST="$PENDING_DIR/$PUB_NAME"
    [ -e "$DEST" ] && fail "publish collided with an existing document at $DEST -- refusing to overwrite; the staged draft is still at $STAGED_REAL"

    mv -n "$STAGED_REAL" "$DEST" 2>/dev/null
    [ ! -e "$STAGED_REAL" ] || fail "publish did not complete -- $STAGED_REAL is still present after mv"
    # mv -n's postcondition check above only proves the source is gone, not
    # that DEST is the plain file we expect: if DEST turned into a directory
    # between the collision check and this mv, mv moves the source *into*
    # it instead of failing, and the source-gone check alone would still
    # report success against the wrong path. Also catches STAGED_REAL being
    # swapped for a symlink after the earlier -L check: mv of a symlink
    # source produces a symlink destination, which this rejects too.
    [ -f "$DEST" ] && [ ! -L "$DEST" ] || fail "publish landed somewhere unexpected -- $DEST is not a plain regular file after mv (directory collision or symlink swap)"
    chmod 600 "$DEST" 2>/dev/null || fail "could not set permissions (0600) on $DEST"

    printf '%s\n' "$DEST"
    exit 0
    ;;
  "")
    STAGING_DIR="$PROJECT_DIR/staging"
    mkdir -p "$STAGING_DIR" 2>/dev/null || fail "could not create $STAGING_DIR"
    chmod 700 "$PROJECT_DIR" "$STAGING_DIR" 2>/dev/null || fail "could not set permissions (0700) on $PROJECT_DIR or $STAGING_DIR"

    TS="$(date -u +%Y%m%dT%H%M%S)"
    TARGET=$(mktemp "$STAGING_DIR/.handoff-$TS.XXXXXX") || fail "could not reserve a staging file"
    printf '%s\n' "$TARGET"
    exit 0
    ;;
  *)
    fail "unknown argument: ${1:-} (usage: handoff-path.sh [--dir | --publish <staging-path>])"
    ;;
esac
