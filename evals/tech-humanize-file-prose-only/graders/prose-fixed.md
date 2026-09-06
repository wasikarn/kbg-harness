---
type: regex
pattern: '\b(delve|robust|landscape|serves as)\b'
match: not_contains
flags: i
target: {source: file, path: README.md}
---
The planted §7/§8 tells in the prose paragraph are gone from the file.
