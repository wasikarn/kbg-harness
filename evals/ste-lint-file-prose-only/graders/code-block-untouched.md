---
type: regex
pattern: '```bash\necho "a;b"\n```'
match: contains
target: {source: file, path: mixed.md}
---
Report-only + code-block-exclusion: the fenced code block, its own semicolon included, is byte-identical after the skill runs.
