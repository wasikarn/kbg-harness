---
type: regex
pattern: '\b(appears to|may have|we believe|probably|likely caused by)\b'
match: not_contains
target: last_message
flags: i
---
The banned-phrase list from step 4 is absent from the delivered record.
