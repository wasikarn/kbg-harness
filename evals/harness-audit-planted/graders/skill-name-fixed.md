---
type: regex
pattern: '\nname: demo\n'
match: contains
target:
  source: file
  path: skills/meta/demo/SKILL.md
---
Check 08 (dir != name) is fixed by restoring the name, not by renaming the directory the prompt names.
