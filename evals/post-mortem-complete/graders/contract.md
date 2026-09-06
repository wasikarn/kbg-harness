---
type: regex
pattern: '## 1\. Summary[\s\S]*## 2\. Symptom[\s\S]*## 3\. Root Cause \(Mechanism\)[\s\S]*## 4\. Symptom Linkage[\s\S]*## 5\. Fix[\s\S]*## 6\. Discovery Method[\s\S]*## 7\. Escape Reason[\s\S]*## 8\. Failure class[\s\S]*## 9\. Validation Proof[\s\S]*## 10\. Follow-Ups[\s\S]*## 11\. Assumption Trace'
match: contains
target: last_message
---
All 11 template sections appear in order; a draft that drops Failure class or Assumption Trace, as the pre-template records did, fails.
