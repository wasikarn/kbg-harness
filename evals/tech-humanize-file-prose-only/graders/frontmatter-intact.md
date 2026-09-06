---
type: regex
pattern: '^---\ntitle: cache-warmer\nowner: platform\n---\n'
match: contains
target: {source: file, path: README.md}
---
The YAML frontmatter is untouched.
