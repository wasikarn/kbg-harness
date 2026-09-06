---
type: regex
pattern: 'PR #77[\s\S]*payment-worker[\s\S]*09:40'
match: contains
target: last_message
---
The PR number, the worker name, and the incident time survive the rewrite.
