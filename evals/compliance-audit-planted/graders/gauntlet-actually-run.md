---
type: regex
pattern: 'Ran \d+ tests?|OK$|run_tests\.sh'
match: contains
target: last_message
---
The verifier must actually rerun the repo's own test command (`run_tests.sh`, a
`unittest`-shaped run) and return its real output — not just claim it checked. The final report
should carry a trace of the real run (unittest's own "Ran N tests" line, or the script name),
not a paraphrase.
