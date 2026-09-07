---
type: regex
pattern: 'total:\s+\$10\.0000\s+\(3 sessions\)'
match: contains
target: last_message
---
The quoted total is the script's deduped figure: the `upgrade-span` session's two rows collapse to the newer $7, plus $2 and $1. A hand sum of the four rows gives $15 and an older-row pick gives $8; the full dedup key is pinned by `tests/skills/test-cost-report.sh`, and `script-ran.md` proves the script produced this line.
