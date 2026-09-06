---
type: regex
pattern: '\]\(rm-f-silently-noops\.md\)'
match: contains
target:
  source: file
  path: memory/MEMORY.md
---
The unindexed, unreachable memory gets a MEMORY.md pointer line; the file itself is kept (never delete, the skill's archive rule).
