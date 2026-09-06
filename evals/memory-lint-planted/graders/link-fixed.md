---
type: regex
pattern: '\[\[push-needs-remote-check\]\]'
match: contains
target:
  source: file
  path: memory/gate-hooks-break-machine-wide.md
---
The dangling link is fixed by correcting the typo to the existing filename stem (the script's did-you-mean hint), not by deleting the link.
