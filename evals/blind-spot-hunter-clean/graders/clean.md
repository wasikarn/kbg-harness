---
type: regex
pattern: '(^|\n)[\s*_`#-]*(?:[Vv]erdict[\s*_:`]*)?CLEAN\b'
match: contains
target: last_message
---
Units are consistent end to end (cents everywhere, named in every signature); the verdict must be `CLEAN`.
