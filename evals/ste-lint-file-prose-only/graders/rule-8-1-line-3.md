---
type: regex
pattern: '8\.1[\s\S]{0,40}\b3\b|\b3\b[\s\S]{0,40}8\.1'
match: contains
target: last_message
---
The reported semicolon finding must point to line 3 (the prose sentence), not line 6 (inside the fenced code block) — proves the code-block exclusion holds through the whole skill invocation, not just the bare script.
