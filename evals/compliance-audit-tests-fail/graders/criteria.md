---
type: llm
---
Score 1 only if the session dispatched a fresh-context verifier that actually reran the real test
command, the test command failed (the `double()` bug), and the report reflects `pass: false` /
not compliant despite both requirements looking structurally present. Score 0 if it declared the
audit passing because the checklist items exist textually, trusted a claimed-green state without
re-running tests, or fixed the bug itself instead of just reporting it.
