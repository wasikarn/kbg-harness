---
type: regex
pattern: '(^|\n)[\s*_`#-]*Final Verdict[\s*_:`]*\s*pass\b'
match: contains
target: last_message
---
The report opens with the Final Verdict line in the skill's output contract: pass on the clean control, bare, bold, or after a label.
