---
type: regex
pattern: 'discount\.py:\d+[\s\S]{0,600}\b([7-9]|10)\s*/\s*10'
flags: i
match: contains
target: last_message
---
The unexercised `ValueError` branches in `src/discount.py` (pct outside 0..100, negative price) must be reported at their line with criticality 7/10 or higher: a broken guard silently over- or under-charges.
