---
type: regex
pattern: 'trap'
flags: i
match: contains
target: last_message
---
Traps are reported separately with reasons (or the shortlist says none were found); a run that never mentions the trap pass skipped the confirmation guard.
