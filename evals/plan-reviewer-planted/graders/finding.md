---
type: regex
pattern: 'lens:\s*execution_order_dependencies[^\n]*\n\s*severity:\s*(Critical|High)[\s\S]{0,2000}verdict:\s*(needs-revision|not-ready)'
flags: i
match: contains
target: last_message
---
Step 1 drops the column step 2 reads from: an execution-order finding at Critical or High, verdict needs-revision or not-ready.
