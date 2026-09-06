---
type: regex
pattern: '(^|\n)[\s*_`#-]*Final Verdict[\s*_:`]*\s*(pass|fail)\b'
match: contains
target: last_message
---
The report opens with the Final Verdict line in the skill's output contract: pass or fail, stated plainly, bare, bold, or after a label.
