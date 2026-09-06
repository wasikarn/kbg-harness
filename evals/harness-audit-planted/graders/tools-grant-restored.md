---
type: regex
pattern: '\ntools: '
match: contains
target:
  source: file
  path: agents/checker.md
---
Check 09 (missing `tools:` grant) is fixed with an explicit grant on the agent.
