---
type: regex
pattern: '(^|\n)\s*COVERED\b'
flags: i
match: contains
target: last_message
---
Every branch, boundary, and error path has a test; the only correct verdict is `COVERED`.
