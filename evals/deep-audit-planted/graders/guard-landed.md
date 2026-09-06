---
type: regex
pattern: '\n\s+if\s+(not\s+total|total\s*(==|<=)\s*0)\b|except\s+ZeroDivisionError'
match: contains
target: {source: file, path: calc.py}
---
The false "guarded" claim is fixed in executable code (an `if` on total or an except clause), not in another docstring.
