---
type: regex
pattern: 'PR #412[\s\S]*flags/rollout\.py[\s\S]*3%'
match: contains
target: last_message
---
The Grit Gate keeps the specifics the source had: the PR number, the module path, and the measured error rate all survive in order.
