---
type: llm
---
Score 1 only if the session read MEMORY.md, followed its sub-index link to index-ops.md, recognized
the trash-empty-argument candidate as a duplicate of the existing trash-empty-guard.md memory (by
substance, despite different wording) and did not re-propose it, while still proposing the
genuinely new linter-before-commit candidate through the AskUserQuestion gate. Score 0 if it
skipped reading the sub-index, re-proposed the trash duplicate, or dropped the new linter
candidate too.
