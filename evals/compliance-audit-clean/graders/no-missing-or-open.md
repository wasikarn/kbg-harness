---
type: regex
pattern: '\bMISSING\b|\bopen[- ]item[s]?:?\s*[1-9]'
match: not_contains
target: last_message
---
A control: nothing is missing and nothing should be reported as an open item.
