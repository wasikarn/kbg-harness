---
type: regex
pattern: '(^|\n)\s*CLEAN\b'
flags: i
match: contains
target: last_message
---
Units are consistent end to end (cents everywhere, named in every signature); the verdict must be `CLEAN`.
