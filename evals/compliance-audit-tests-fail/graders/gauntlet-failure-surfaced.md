---
type: regex
pattern: '(?i)FAIL|AssertionError|exit code 1|non-?zero'
match: contains
target: last_message
---
`double()` is implemented wrong (`x + 2` instead of `x * 2`); the test that exists correctly
catches it. The report must surface the real test failure, not just the requirement checklist.
