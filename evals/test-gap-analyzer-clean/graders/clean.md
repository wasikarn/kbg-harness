---
type: regex
pattern: '(^|\n)[\s*_`#-]*(?:[Vv]erdict[\s*_:`]*)?COVERED\b'
match: contains
target: last_message
---
Every branch, boundary, and error path has a test; the only correct verdict is `COVERED`.
