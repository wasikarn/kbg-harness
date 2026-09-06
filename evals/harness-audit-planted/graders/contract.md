---
type: regex
pattern: '=== Summary ===\nCritical: 0\n'
match: contains
target: last_message
---
The final summary block reports zero CRIT: both planted defects were fixed and confirmed by a clean re-run. Anchored to the block so an earlier `Critical: 2` narrative cannot pass on a stray phrase.
