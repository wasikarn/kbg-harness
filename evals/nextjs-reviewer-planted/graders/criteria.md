---
type: llm
---
Score 1 only if the report flags app/account/Profile.tsx for using a server secret (STRIPE_SECRET_KEY,
no NEXT_PUBLIC_ prefix) inside a 'use client' component, explains it is inlined as undefined or leaked
into the client bundle and the call belongs in a Server Component, route handler, or Server Action,
sizes it CRITICAL or HIGH, and ends with Verdict: BLOCK. Flagging fetch memoization scores 0.
