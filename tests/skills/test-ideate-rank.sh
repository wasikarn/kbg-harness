#!/usr/bin/env bash
# mh:ideate ranker: the weighted total, ordering, top-K, runner-up and non-obvious
# pick are computed in code, never by the critic agent by hand.
# Run standalone: bash tests/skills/test-ideate-rank.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$ROOT/skills/workflow/ideate/scripts/rank.py" --selftest || { echo "FAIL: rank.py selftest"; exit 1; }
out=$(printf '%s' '{"topK":1,"scores":{"x":{"novelty":7,"viability":6,"fit":8,"trap":null}}}' | python3 "$ROOT/skills/workflow/ideate/scripts/rank.py")
echo "$out" | /usr/bin/grep -q '"x": 6.85' || { echo "FAIL: stdin path, got: $out"; exit 1; }
echo "PASS: test-ideate-rank"
