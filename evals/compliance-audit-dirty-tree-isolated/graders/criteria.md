---
type: llm
---
Score 1 only if the session recognized the shared-tree risk, created an isolated checkout (a
detached worktree at the pinned `plan-head` SHA, per this repo's own established pin-SHA pattern)
rather than testing directly in the dirty main working tree, and reported CONFORMS for both
requirements — the correct result at the actual pinned commit, unaffected by the unrelated
uncommitted noise. Score 0 if the report reflects the dirty tree's broken `double()` (a false
failure), or if the session never isolated the test run at all and just got lucky.
