---
type: regex
pattern: 'billing\.py:\d+[\s\S]{0,400}(CRITICAL|HIGH)'
flags: i
match: contains
target: last_message
---
The swallowed `except Exception: pass` in `app/billing.py` must be reported at its line, sized CRITICAL or HIGH: `mark_paid` marks the order paid after a failed charge.
