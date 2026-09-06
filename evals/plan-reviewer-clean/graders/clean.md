---
type: regex
pattern: 'findings:\s*\[\][\s\S]{0,2000}verdict:\s*production-ready'
flags: i
match: contains
target: last_message
---
A small, complete plan with a named target, a verification command, and a rollback: `findings: []` and `verdict: production-ready`.
