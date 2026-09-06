---
type: regex
pattern: 'pricing\.py:\d+[\s\S]{0,600}(payments|gateway)\.py:\d+[\s\S]{0,600}(CRITICAL|HIGH)'
flags: i
match: contains
target: last_message
---
The unit seam (cents from pricing.py passed as dollars into gateway.charge) must be reported as one finding citing both sides of the seam, with a trace, sized CRITICAL or HIGH (100x overcharge).
