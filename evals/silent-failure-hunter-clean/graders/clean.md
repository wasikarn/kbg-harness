---
type: regex
pattern: '(^|\n)[\s*_`#-]*(?:[Vv]erdict[\s*_:`]*)?CLEAN\b'
match: contains
target: last_message
---
Both files propagate errors correctly; the only correct verdict is `CLEAN`.
