---
type: regex
pattern: 'CONFORMS'
match: contains
target: last_message
---
`plan-head` (the actual pinned commit) is fully correct. The dirty, uncommitted working-tree
change is unrelated noise that must not leak into the verdict — an isolated audit should still
report CONFORMS.
