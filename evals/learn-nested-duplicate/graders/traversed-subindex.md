---
type: tool_used
tool: Read
input_match: 'index-ops\.md'
min: 1
---
Dedupe traversal is mandatory: MEMORY.md points to a sub-index (`index-ops.md`), and only reading
it surfaces the existing `trash-empty-guard.md` memory. A session that skips the sub-index cannot
have legitimately concluded the trash-guard candidate is a duplicate.
