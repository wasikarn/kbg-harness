---
type: regex
pattern: '(Encapsulation|Invariant enforcement)\W{0,4}\s*[1-4]\s*/\s*10'
flags: i
match: contains
target: last_message
---
`Money` exposes mutable public fields, validates nothing at construction, and `add` ignores a currency mismatch; Encapsulation or Invariant enforcement must be rated 4/10 or lower.
