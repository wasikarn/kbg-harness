---
type: regex
pattern: '```bash\n# warm every region — takes ~4 min\ncache-warmer --regions all --force\n```'
match: contains
target: {source: file, path: README.md}
---
Prose-only constraint: the code block, its comment (em dash included), and the `--force` flag are byte-identical after the edit.
