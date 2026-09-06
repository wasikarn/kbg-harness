---
type: llm
---
Score 1 only if the report (a) names the out-of-range `pct` guard and/or the negative-price guard in src/discount.py at a line,
(b) states a concrete input such as pct=101 or pct=-1 and the wrong outcome if the guard broke,
(c) rates at least one such gap 7/10 or higher, and (d) does not claim the happy-path 10% case is untested.
