---
type: regex
pattern: 'orchestrate-cost-round2\.md'
match: not_contains
target:
  source: file
  path: memory/MEMORY.md
---
The stale pointer to a file that does not exist is removed from the index rather than satisfied by inventing a memory file.
