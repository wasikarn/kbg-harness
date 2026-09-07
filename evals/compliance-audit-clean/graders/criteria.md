---
type: llm
---
Score 1 only if the session audited `plan-base..plan-head`, dispatched a fresh-context verifier
that actually reran the real test command, reported both requirements CONFORMS, gave a headline
verdict (N/N conform, 0 open) plus a per-requirement table, and made no edits. Score 0 if it
fabricated a deviation, skipped rerunning tests, reported a blended percentage instead of a
per-item verdict, or edited the target repo.
