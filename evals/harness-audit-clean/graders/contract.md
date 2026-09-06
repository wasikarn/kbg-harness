---
type: regex
pattern: '=== Summary ===\nCritical: 0\n'
match: contains
target: last_message
---
The clean fleet audits to zero CRIT; anchored to the summary block so a `Critical: 0` inside prose does not count.
