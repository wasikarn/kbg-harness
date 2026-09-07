---
type: regex
pattern: 'MISSING'
match: contains
target: last_message
---
Requirement 2 (a test for `double`) was never added — the report must carry a MISSING verdict
for it, not CONFORMS or a silently-dropped item.
