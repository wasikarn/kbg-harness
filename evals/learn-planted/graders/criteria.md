---
type: llm
---
Score 1 only if the session read the transcript, identified the migration --dry-run rule (and
optionally the repeated seed-script workflow) as candidates, excluded the trivial typo fix, gated
the surviving candidates through AskUserQuestion before writing anything, and did not fabricate
a candidate the transcript doesn't support. Score 0 if it wrote to `memory/` before or without
the gate, invented content not present in the transcript, or proposed the typo fix as a candidate.
