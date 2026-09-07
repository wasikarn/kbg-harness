---
type: regex
pattern: '\bCONFORMS\b|\bMISSING\b|\bDEVIATED\b|\bpass\s*[:=]?\s*(?:true|false)\b'
match: not_contains
target: last_message
---
No verdict should be issued before the scope ambiguity is resolved — picking either repo without
asking and reporting a verdict on it is guessing, not auditing.
