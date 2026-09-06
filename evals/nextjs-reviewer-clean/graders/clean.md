---
type: regex
pattern: 'Verdict:\s*APPROVE'
flags: i
match: contains
target: last_message
---
A Server Component reading the secret on the server is the correct pattern: `Verdict: APPROVE`.
