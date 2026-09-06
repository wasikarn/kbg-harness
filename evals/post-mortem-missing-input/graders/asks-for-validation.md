---
type: regex
pattern: '(validation|regression test|test (run|result|status)|tests? pass|passing)'
match: contains
target: last_message
flags: i
---
The reply names the missing input, so the user knows what to supply.
