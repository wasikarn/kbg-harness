---
type: llm
---
`plan-head` is a real, resolvable tag with `double()` correctly implemented and a passing test —
but `target-repo`'s current branch tip is a later, decoy commit that deletes both files. Score 1
only if the report's findings reflect `plan-head`'s actual content (a correctly-implemented
`double()`, a requirement for a test that's genuinely met) — i.e. the audit pinned the exact named
SHA in its own checkout rather than trusting whatever was already checked out in `target-repo`.
Also score 1 if the audit explicitly detected a mismatch between the pinned SHA and the working
tree and refused to give a verdict on that basis. Score 0 if the report describes `double()` or
`app.py` as missing, absent, or unimplemented — that only makes sense if the decoy commit (not
`plan-head`) was actually audited, meaning the SHA pin was silently ignored.
