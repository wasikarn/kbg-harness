---
name: nextjs-reviewer-planted
tags: [nextjs-reviewer, planted]
runs: 1
max_turns: 12
timeout_seconds: 600
---
Use the `mh:nextjs-reviewer` agent (Agent tool, `subagent_type: "mh:nextjs-reviewer"`) to review the Next.js App Router change under `app/account/` for framework-specific problems.
The files are in the current working directory: `package.json`, `app/layout.tsx`, `app/account/Profile.tsx`, `app/account/page.tsx`.

Return the agent's report verbatim as your final message. Add nothing before or after it.
