#!/usr/bin/env bash
# Sensor: on a Bash command's non-zero exit, inject a diagnose-before-retry
# nudge (additionalContext) into the same turn. Advisory only -- never denies,
# never blocks; always exits 0. GH #153. Not an autonomous loop: fires only
# inside a turn a human already started, and injects text, never dispatches.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:sensor] python3 not found — failure-diagnose-nudge cannot run; allowing (install python3 to restore the diagnose-before-retry nudge)" >&2
  exit 0
fi

_py="$(dirname "$0")/failure-diagnose-nudge.py"
if [ ! -r "$_py" ]; then
  echo "[mh:sensor] internal error: sibling script failure-diagnose-nudge.py missing or unreadable — allowing (fail-safe = allow, same posture as this sensor's own parse-error path)" >&2
  exit 0
fi

python3 "$_py" "$@"
exit 0
