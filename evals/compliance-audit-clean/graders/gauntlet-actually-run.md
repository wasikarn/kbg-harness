---
type: regex
pattern: 'Ran \d+ tests?|OK$|run_tests\.sh'
match: contains
target: last_message
---
The verifier must actually rerun the test command and return real output — a clean plan is not
an excuse to trust a claimed-green state without re-running it.
