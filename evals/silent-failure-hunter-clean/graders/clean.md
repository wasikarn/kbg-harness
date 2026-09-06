---
type: regex
pattern: '(^|\n)\s*CLEAN\b'
flags: i
match: contains
target: last_message
---
Both files propagate errors correctly; the only correct verdict is `CLEAN`.
