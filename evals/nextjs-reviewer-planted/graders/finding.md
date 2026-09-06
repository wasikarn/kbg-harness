---
type: regex
pattern: 'Profile\.tsx[\s\S]{0,1500}(CRITICAL|HIGH)[\s\S]{0,3000}Verdict:\s*BLOCK'
flags: i
match: contains
target: last_message
---
`process.env.STRIPE_SECRET_KEY` inside a `'use client'` component ships the secret to the browser bundle: CRITICAL or HIGH on Profile.tsx and `Verdict: BLOCK`.
