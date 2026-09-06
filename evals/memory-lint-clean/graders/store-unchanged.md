---
type: regex
pattern: '^# Memory index\n\n- \[Gate hooks break machine-wide\]\(gate-hooks-break-machine-wide\.md\) — on a lockout, check every session\.\n- \[Push needs a remote check\]\(push-needs-remote-check\.md\) — ls-remote before saying it landed\.\n- \[Trash with empty arg deletes cwd\]\(trash-empty-arg-deletes-cwd\.md\) — validate non-empty first\.\n$'
match: contains
target:
  source: file
  path: memory/MEMORY.md
---
The index is byte-identical to the scaffold: the same proof as `no-edits.md` and `no-writes.md`, on the file rather than the tool log, since `max` on `tool_used` is unverified against the runner.
