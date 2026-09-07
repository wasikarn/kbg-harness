---
type: tool_used
tool: Bash
input_match: 'worktree add.*--detach'
min: 1
---
Isolation must go through a real mechanism, not luck: a detached `git worktree add` at the
pinned SHA, per this repo's own established pattern for shared-tree audits.
