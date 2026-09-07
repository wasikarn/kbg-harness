# Codex CLI delegation — official docs + oh-my-claudecode field study (2026-09-07)

**Date:** 2026-09-07. **Scope:** two independent questions, kept separate below. (1) What OpenAI's
own docs and the `openai/codex` repo say about `codex exec`, sandboxing, approvals, and any
documented mechanism for another program to drive Codex. (2) How a real third-party harness
(`oh-my-claudecode`, local clone) actually wires Claude↔Codex delegation in code. Section 3
compares both to this repo's own `docs/reference/codex-integration-map.md`. **No changes made
to matt-harness** — research only, per the requesting task.

**Method:** WebFetch/WebSearch against official sources (`developers.openai.com/codex/*`, which
308-redirects to `learn.chatgpt.com/docs/*` — same redirect this repo's own
`docs/research/native-tools-claude-code-vs-codex-2026-09-06.md` recorded a day earlier), `gh api`
against `openai/codex`, and a local `codex --version` check. Section 1 reuses and cross-checks
that prior in-repo note rather than re-deriving facts it already verified — it is credited inline
wherever reused, and every reused claim was re-confirmed against a live fetch today, not copied
blind. Section 2 is direct `Read`/`Grep` of `~/Codes/Personals/oh-my-claudecode` (a separate,
read-only local repo — no edits made there).

---

## TL;DR

1. **The official docs domain moved.** `developers.openai.com/codex/*` now 308-redirects to
   `learn.chatgpt.com/docs/*`. Both this note and yesterday's `native-tools-claude-code-vs-codex`
   note hit the same redirect independently — treat `developers.openai.com` as a stable *entry*
   URL and `learn.chatgpt.com` as the URL that actually resolves.
2. **`codex exec` is the scripted/CI entry point**: read-only sandbox by default, `--json` emits
   JSONL turn/item events, `-o/--output-last-message` and `--output-schema` give structured
   single-shot output, `resume`/`fork`/`review` subcommands reattach to prior sessions.
3. **The documented "call Codex from another agent" surface is the app-server** (JSON-RPC 2.0
   over stdio/WebSocket/Unix socket) — the same one this repo's own `codex@openai-codex` plugin
   already drives (`scripts/lib/codex.mjs`, cited in the prior note). **`codex mcp-server` — the
   literal MCP-server mode — is now documented as deprecated in favor of the app-server**: "Use
   the Codex app server instead" (`learn.chatgpt.com/docs/mcp-server`, fetched today). This is a
   new fact not in yesterday's note.
4. **Auth is three-tier**: `codex login` (ChatGPT OAuth, default, plan credits), API key piped to
   `codex login --with-api-key` (standard API billing, some ChatGPT-workspace features
   unavailable), and enterprise access tokens for CI (`codex login --with-access-token`). CI
   guidance is to persist `auth.json` across runs and let Codex's built-in ~8-day refresh handle
   renewal, never to reseed on every job.
5. **Rate limits are plan-shaped, not API-shaped.** ChatGPT-plan usage is "local messages per
   five-hour period," model- and plan-tier dependent, plus a weekly cap; API-key usage has no
   fixed message count, just token-metered billing at standard API rates. (Specific message-count
   figures the fetch tool reported are not repeated here — see §1.4's caveat on summarizer
   fidelity.)
6. **oh-my-claudecode deprecated MCP-based Codex/Gemini delegation entirely.** Its own
   `delegation-routing/resolver.ts` treats `codex`/`gemini` as `DEPRECATED_MCP_PROVIDERS`, warns,
   and reroutes to a Claude subagent. The live mechanism is `/team`'s **tmux-pane CLI workers**:
   `codex` is launched as a persistent interactive process in a tmux pane (explicitly *not*
   `codex exec`), fed via an `inbox.md` file, and polled/nudged — a design choice with an inline
   comment explaining why one-shot exec was rejected for this path.
7. **A second, older code path still uses one-shot `codex exec --json`** (`mcp-team-bridge.ts`'s
   `spawnCliProcess`), explicitly marked `@deprecated` at the file's own top comment but "retained
   for the tmux bridge daemon functionality" — i.e., still load-bearing, just not the MCP-exposed
   entry point it once was.
8. **Fallback on missing CLI is deterministic, not silent**: `buildLaunchArgs()` throws when a
   binary isn't on `PATH`, the team lead posts a visible warning, and the runtime substitutes a
   pre-computed Claude assignment from the same routing snapshot — unless Claude itself is also
   unavailable, in which case it says so rather than claiming a fallback exists.
9. **matt-harness and oh-my-claudecode arrived at compatible but differently-shaped answers** to
   the same problem (Codex as a second, independent coding agent): mh treats the app-server as the
   one integration point and gates almost nothing Codex-side (git hooks are the floor); OMC treats
   Codex as one of six interchangeable CLI-worker backends behind a uniform contract, with no
   Codex-specific gate either — see §3.

---

## 1. Codex CLI — official-doc findings

### 1.1 Where the docs live, and version ground-truth

- Canonical docs root: `developers.openai.com/codex` → 308 → `learn.chatgpt.com/docs`. Verified
  live today on three separate pages (`/codex/auth.md`, `/codex/auth/ci-cd-auth`,
  `/codex/pricing`), each redirecting to the `learn.chatgpt.com/docs/...` equivalent. The prior
  in-repo note (`native-tools-claude-code-vs-codex-2026-09-06.md:3-4`) recorded the identical
  redirect one day earlier — this is now confirmed twice, independently, one day apart.
- Repo: `github.com/openai/codex`, Apache-2.0, description "Lightweight coding agent that runs in
  your terminal" (`gh api repos/openai/codex`, fetched today: `pushed_at: 2026-09-07T06:45:44Z`,
  `stargazers_count: 122091`) — actively maintained, pushed to same-day as this research.
- **Version ground truth**: local `codex --version` → `codex-cli 0.153.4`. `gh api
  repos/openai/codex/releases/latest` confirms `tag_name: rust-v0.153.4`, `published_at:
  2026-09-04T23:25:48Z`. This matches the version the prior in-repo note used
  (`native-tools-claude-code-vs-codex-2026-09-06.md:5`) — no version drift in the day between the
  two notes. The 0.153.4 patch notes are cosmetic (model-picker visibility fix for a model
  codenamed "Astra"), not behavior-relevant to anything below.
- README (`raw.githubusercontent.com/openai/codex/main/README.md`, fetched today): distinguishes
  **Codex CLI** (local terminal agent, this note's subject) from **Codex IDE extension**, the
  **Codex desktop app** (`codex app`), and **Codex Web** (`chatgpt.com/codex`, a *cloud-based*
  agent) — four different products share the "Codex" name; only the CLI is in scope here or in
  matt-harness's pairing.

### 1.2 `codex exec` — non-interactive/scripted mode

Fetched fresh today (`learn.chatgpt.com/docs/non-interactive-mode.md`, redirected from
`developers.openai.com/codex/noninteractive`), and cross-checked against
`native-tools-claude-code-vs-codex-2026-09-06.md:112-137` (itself sourced to the same page plus
`codex exec --help`) — the two agree on every flag, so nothing here is disputed, only confirmed
twice a day apart.

- **Sandbox modes** (`sandbox_mode`, `--sandbox`/`-s`): `read-only` (inspect only, no edits or
  unapproved commands), `workspace-write` (the documented default for local work), and
  `danger-full-access` (removes filesystem and network boundaries entirely). `codex exec` defaults
  to `read-only`; the page's own example for opting into edits is
  `codex exec --sandbox workspace-write "<task>"`.
- **Approval modes** (`approval_policy`, `--ask-for-approval`/`-a`): `untrusted` (ask before
  anything outside a trusted command set), `on-request` (model asks only when it must leave the
  sandbox), `never` (no prompts; failures are returned to the model as failures, not surfaced to a
  human) — plus a granular table (`sandbox_approval`, `rules`, `mcp_elicitations`,
  `request_permissions`, `skill_approval`). `on-failure` is documented as deprecated.
  `--dangerously-bypass-approvals-and-sandbox` = full access + `never` in one flag;
  `--full-auto` is deprecated and now prints a warning. (The non-interactive-mode page itself
  doesn't spell out approval-mode behavior in the section fetched today — this bullet's detail is
  the reused, not re-confirmed, half of this sub-section.)
- **Output format**: progress goes to stderr, the final assistant message to stdout; `--json`
  switches to JSONL events — confirmed today as `thread.started`, `turn.started`, `turn.completed`,
  `turn.failed`, `item.*` (agent messages, reasoning, command executions, file changes, MCP tool
  calls, web searches, plan updates), and `error` (a superset of yesterday's note, which only
  listed `thread.started`/`turn.completed`/`item.completed`/`error`); `-o/--output-last-message`
  writes just the final message to a file; `--output-schema` constrains the final message to a
  JSON schema — this is the structured-output path a calling script would use to parse a verdict
  deterministically rather than scraping prose.
- **Session controls**: `codex exec resume --last` (continue the previous session) and
  `codex exec resume <SESSION_ID>` (a specific one), plus `fork` and `review` subcommands;
  `--ephemeral` (don't persist the session), `--skip-git-repo-check`, `--ignore-user-config`,
  `--ignore-rules`.
- **CI auth shortcut specific to `exec`**: the page recommends passing `CODEX_API_KEY` inline
  for CI rather than a persistent login, "to avoid exposing credentials to untrusted code
  processes" — a narrower, `exec`-specific pattern than the `auth.json`-persistence guidance in
  §1.4, which is for the interactive/app-server auth path.
- **Exit codes**: confirmed today, still not tabulated anywhere on this page. The one documented
  behavior class that matters operationally is the "silent refusal" case matt-harness's own
  integration map already tracks — see §3.

### 1.3 Delegating to Codex from another program — three documented mechanisms, one now deprecated

This is the part of the task with the most day-over-day news, so it was re-fetched fresh rather
than reused:

1. **`codex exec` as a subprocess** (spawn it, read stdout/stderr, parse `--json` or
   `--output-schema` output). Not a special "integration mode" — it's just the CLI's normal
   non-interactive behavior, and it's what both matt-harness's `compliance-audit` Phase 2 and
   oh-my-claudecode's older bridge code (§2.3) actually do in practice.
2. **The app-server**: JSON-RPC 2.0 over stdio, WebSocket, or a Unix socket.
   `thread/start`/`thread/resume`/`thread/fork`, `turn/start`/`turn/steer`/`turn/interrupt`,
   `review/start`; per-turn overrides for `model`, `effort`, `cwd`, `sandboxPolicy`,
   `approvalPolicy` persist as thread defaults; approvals arrive as
   `item/commandExecution/requestApproval` / `item/fileChange/requestApproval` events the caller
   must answer. (`learn.chatgpt.com/docs/app-server`, reused from
   `native-tools-claude-code-vs-codex-2026-09-06.md:139-145`, not re-fetched today — no reason to
   expect churn and the app-server is already this repo's own plugin's documented integration
   point.) `codex mcp-server` additionally exposes *Codex itself* over MCP stdio.
3. **`codex mcp-server` — MCP server mode — is documented as deprecated as of today's fetch.**
   Fetched fresh (`learn.chatgpt.com/docs/mcp-server`, 2026-09-07): starting it is `codex
   mcp-server`; it exposes exactly two tools, `codex` (start a session: prompt +
   `approval-policy`/`base-instructions`/`model`/`sandbox`/`cwd` overrides) and `codex-reply`
   (continue a session: `prompt` + `threadId`, both required, where `threadId` comes from the
   `structuredContent.threadId` field of the prior `tools/call` response). The doc's own words:
   *"`codex mcp-server` is deprecated. Use the Codex app server instead."* This line was **not**
   present in, or at least not surfaced by, yesterday's in-repo note (which listed `codex
   mcp-server` only as an existence fact from `codex --help`, flagged as "not in the fetched MCP
   page" — `native-tools-claude-code-vs-codex-2026-09-06.md:213-214`). Today's direct fetch of the
   MCP-server doc page closes that gap and adds the deprecation notice as new information.
   Practical implication for anyone integrating fresh: **the app-server, not `codex mcp-server`,
   is the currently-recommended programmatic entry point** — which matches what matt-harness's own
   `codex@openai-codex` plugin already does (app-server via `scripts/lib/codex.mjs`, per
   `codex-integration-map.md`'s sandbox note) and gives independent, official confirmation that
   choice tracks upstream's current recommendation, not a stale one.
4. Secondary/unofficial sources (DeepWiki's `openai/codex` wiki, a third-party blog) describe the
   same two-tool (`codex`/`codex-reply`) contract and note a real limitation — `codex-reply` only
   works while the *same* server process still holds the conversation in an in-memory
   `ConversationManager`; a fresh `codex mcp-server` process (or one that exited) has nothing to
   resume. This is **not from an official page** — flagged as secondary per the task's sourcing
   rule — but it is consistent with, and explains *why*, the official docs now steer integrators
   toward the app-server's persisted `thread/resume` instead.

### 1.4 Auth and rate limits (new research — not covered by the prior in-repo note)

Fetched today, `learn.chatgpt.com/docs/auth.md` (redirected from `developers.openai.com/codex/auth.md`):

- **ChatGPT login (default)**: `codex login` → browser OAuth. Quoted: *"This is the default
  authentication path when no valid session is available."* Follows the signed-in ChatGPT
  workspace's plan and enterprise retention settings.
- **API key**: piped to login rather than passed as a flag — *"Pipe the key to `codex login`
  through stdin: `printenv OPENAI_API_KEY | codex login --with-api-key`"*. Billed at standard
  OpenAI Platform API rates; the doc is explicit that *"some features that rely on ChatGPT
  workspace access or cloud services are limited or unavailable"* under this mode.
- **Enterprise access tokens**: `printenv CODEX_ACCESS_TOKEN | codex login --with-access-token`,
  intended per the doc *"for trusted scripts, schedulers, and private CI runners"* needing
  workspace access without an interactive browser sign-in.
- **CI/CD persistence** (`learn.chatgpt.com/docs/auth/ci-cd-auth.md`, fetched today): Codex caches
  auth in `auth.json` under `$CODEX_HOME` (default `$HOME/.codex`); a `last_refresh` older than
  "about 8 days" triggers an automatic silent refresh on the next run, which rewrites both the
  token bundle and `last_refresh`. The documented pattern for **self-hosted/persistent runners**
  is: seed once, let Codex refresh in place, never re-seed from a stale copy. For **ephemeral
  runners**: restore `auth.json` before the run, persist the *post-run* (possibly refreshed) file
  afterward — explicitly warned not to persist the original seed instead. `auth.json` is called
  out as password-equivalent (never commit, never log, never share across concurrent jobs).
  `cli_auth_credentials_store = "file"` in config controls this storage mode.
- **Rate limits** (`learn.chatgpt.com/docs/pricing`, fetched today): framed as *"local messages per
  five-hour period,"* model- and plan-tier dependent, plus a stated weekly cap layered on top:
  *"Local messages and cloud chats share your plan's usage allowance. Weekly limits may also
  apply."* No fixed request/token ceiling is published for API-key mode — it's continuously
  metered at standard API pricing instead. **Caveat**: WebFetch summarizes a page through its own
  small model rather than returning raw text, and it reported specific example numbers (roughly
  10–100 messages/window on one plan tier scaling to 200–2,000 on a higher tier for "the same
  model") that this note did not see verbatim and cannot independently confirm — they are omitted
  above rather than repeated as fact; treat the qualitative shape (five-hour local-message
  windows, plan/model-tier dependent, weekly cap on top, API key = pure token metering) as the
  verified claim, and re-fetch the pricing page directly (not through a summarizer) before citing
  any specific number. The practical guidance embedded in the docs: use a ChatGPT account when you
  want Codex-specific rate limits bundled with a plan; use an API key when you want
  CI/automation-friendly, provision-and-rotate-able credentials with no session/browser
  dependency, accepting metered billing in exchange.

### 1.5 What was, and wasn't, independently re-verified today

Re-fetched and confirmed fresh today: the version (§1.1), the `codex exec` flag/output/session
surface (§1.2, including a fuller `--json` event list than yesterday's note had), auth and CI
persistence (§1.4), rate limits (§1.4), and the MCP-server deprecation notice (§1.3 point 3).
**Not** independently re-fetched today, carried over from
`native-tools-claude-code-vs-codex-2026-09-06.md` on the reasoning that an RPC method-name surface
is unlikely to churn day-to-day: the app-server's JSON-RPC method list in §1.3 point 2, and the
approval-mode *behavior* description inside §1.2 (the mode *names* were re-confirmed; the
behavioral description of each was not re-shown on today's fetch of the non-interactive-mode
page).

---

## 2. oh-my-claudecode — Claude↔Codex delegation, from source

Repo: `~/Codes/Personals/oh-my-claudecode` (local clone, read-only exploration, no edits made).
All citations are `path:line` against files read directly.

### 2.1 Two eras, both present in the codebase today

The repo shows its own migration in-line. There are **two different Codex-delegation mechanisms**
coexisting, one deprecated-but-still-referenced and one current:

- **Deprecated: MCP-server-based delegation.** `src/features/delegation-routing/resolver.ts:20-23`
  defines `DEPRECATED_MCP_PROVIDERS = new Set([...])` containing `'codex'` and `'gemini'`; any
  config that names `codex`/`gemini` as a role's provider triggers a `console.warn` with the fixed
  text at `resolver.ts:25-26`: *"[OMC] Codex/Gemini MCP delegation is deprecated. Use /team to
  coordinate CLI workers instead."* The actual resolution at `resolver.ts:91-102`
  (`resolveFromConfig`) discards the deprecated provider and routes to a Claude `Task` dispatch
  instead, keeping the originally-requested Codex agent name only as diagnostic text in the
  `reason` field — the dispatch itself always executes as Claude. `isDeprecatedMcpProvider()` at
  `resolver.ts:154-158` is the single choke point both call sites check.
  `docs/MIGRATION.md:129-173` documents the same deprecation at the tool-surface level: legacy
  `omc_run_team_start/status/wait/cleanup` MCP tools now hard-return
  `{"code": "deprecated_cli_only", ...}` at runtime, with the CLI (`omc team ...`) as the
  replacement — this is a distinct, additional MCP-runtime deprecation on top of the
  per-role-routing one in `resolver.ts`, but the direction is the same: **away from MCP tool
  calls, toward CLI-first execution.**
- **Current: tmux-pane CLI workers via `/team`.** `skills/team/SKILL.md:584-642` ("CLI Workers
  (Codex and Gemini)") documents `codex_worker` as one of four execution modes alongside
  `claude_worker`, `gemini_worker`, `antigravity_worker`: *"Codex CLI (tmux pane) — Full filesystem
  access in working_directory. Runs autonomously via tmux pane."* This is the mechanism actually
  reachable today via `/team 2:codex "<task>"` (`skills/team/SKILL.md:38-39`).

### 2.2 What triggers a handoff

Two entry points, both user- or lead-initiated (nothing autonomous triggers a Codex handoff on its
own):

- `/team N:codex "<task>"` — explicit CLI-agent-type parameter on the team skill
  (`skills/team/SKILL.md:26`, `:886`: `ops.defaultAgentType` config key, values include
  `'codex'` — `src/cli/team.ts:19`, `src/cli/commands/team.ts:29` both enumerate
  `'codex'` in `VALID_(TEAM_)CLI_AGENT_TYPES`).
- **Per-role routing**: `.claude/omc.jsonc`'s `team.roleRouting.<role>.provider: "codex"`
  (`skills/team/SKILL.md:896-955`) lets the lead pin specific pipeline roles (e.g. `critic`) to
  Codex while others stay Claude — resolved once at team creation and frozen for the team's
  lifetime (`SKILL.md:961-963`, "Stickiness — resolved once, reused everywhere").
- A lighter-weight, single-shot path exists too: `/oh-my-claudecode:ask codex "<question>"`
  (`skills/ask/SKILL.md:19`) — one prompt, one CLI invocation, output persisted as an artifact
  file rather than routed through the team pipeline. The skill file is explicit that the model
  itself must not hand-assemble the Codex CLI invocation: *"Do NOT manually construct raw provider
  CLI commands... The `omc ask` wrapper handles correct flag selection"* (`ask/SKILL.md:34`) — the
  actual `codex` invocation happens inside `omc`'s own compiled CLI (`src/cli/ask.ts`), not in the
  calling agent's turn.

### 2.3 The actual invocation mechanism — two code paths, matching the two eras

**Current (`/team`'s `codex_worker`) — persistent tmux pane, not `codex exec`.**
`src/team/model-contract.ts:209-240` defines the `codex` entry in the `CONTRACTS` table
(`model-contract.ts:185`). The comment at `model-contract.ts:213-215` states the design decision
directly: *"Team workers must be persistent interactive panes. Do not use `codex exec` or
positional prompt mode here; runtime dispatch writes inbox.md and nudges the live Codex TUI with
`codex` as the worker process."* `buildLaunchArgs()` for codex
(`model-contract.ts:217-221`) returns just `['--dangerously-bypass-approvals-and-sandbox',
'--model', <model>]` — i.e., the pane launches the interactive Codex TUI directly (full access,
no approval prompts), not a one-shot `exec` subcommand. `supportsPromptMode: false`
(`model-contract.ts:216`) marks codex (and, identically, `cursor`) as needing the persistent-pane
path rather than the `-p/--print` one-shot flag path gemini/grok/antigravity use.
Once the pane is up, task instructions are delivered by **writing to a per-worker `inbox.md`
file** (`src/team/worker-bootstrap.ts:55,65,189`; path constructed at
`buildTeamStateInstructionPath(teamName, ..., 'workers', workerName, 'inbox.md')`) and the live
pane is nudged to read it — the mechanism referenced by the model-contract.ts comment above and by
`src/team/idle-nudge.ts` (nudge logic; not read in full for this note). `worker-bootstrap.ts:130-136`
supplies codex-specific guidance text injected into the worker's context: *"Prefer short, explicit
`omc team api ... --json` commands... If a command fails, report the exact stderr to leader-fixed
before retrying."* — i.e., the worker is told to talk back to the lead via `omc`'s own CLI API,
not via any Codex-native session-sharing feature.

**Deprecated-but-retained (`mcp-team-bridge.ts`) — one-shot `codex exec --json` subprocess.**
The file's own header (`src/team/mcp-team-bridge.ts:1-12`) reads: *"@deprecated The MCP x/g servers
have been removed. This bridge now runs against tmux-based CLI workers... retained for the tmux
bridge daemon functionality."* Despite the deprecation tag, `spawnCliProcess()`
(`mcp-team-bridge.ts:453-476`) still constructs and spawns a genuine `codex exec` call:
```
cmd = "codex"
args = ["exec", "-m", <model>, "--json",
        "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check"]
```
run via Node's `spawn()` with piped stdio and a hard timeout (`mcp-team-bridge.ts:483-500`),
prompt delivered over stdin, stdout parsed by a `parseCodexOutput()` helper
(`mcp-team-bridge.ts:400-447`). Reading its body rather than assuming: it scans every JSONL line,
collects text from **three** event shapes (`item.completed` with `item.type === "agent_message"`,
`message` with a string-or-array `content`, and `output_text`), and returns
`messages.join("\n") || output` — i.e. it **concatenates every matching message it finds**, in
order, with a 1MB truncation guard (`MAX_CODEX_OUTPUT_SIZE`, `mcp-team-bridge.ts:398`). This is
**not** the same shape as the current codex contract's own `parseOutput()`
(`model-contract.ts:222-239`), which walks the lines **backward** and returns only the **first
match from the end** (`type === "message" && role === "assistant"`, or a `result`/`output` field)
— i.e. the single last assistant message, not a join of everything. Two different parsers for the
same JSONL stream, written for two different eras of the same codebase, disagree on whether
"Codex's answer" means the last message or the concatenation of all of them — worth flagging as an
internal inconsistency in OMC's own code, not something this note is asserting a preference on.
Despite that internal difference, both OMC parsers and matt-harness's own `compliance-audit`
Phase 2 dispatch (`codex-integration-map.md:19`: "a raw `codex exec` (workspace-write, scoped to a
disposable pinned worktree)") converge on the same higher-level pattern: spawn `codex exec --json`,
parse the JSONL stream, extract assistant text as the verdict — the disagreement is only in *which*
text counts as the answer when there's more than one message.

### 2.4 Getting Codex's output back into the session

Two return paths, matching the two invocation mechanisms:

- **tmux-pane workers** cannot use Claude Code's native team/conversation messaging or task-list
  tools at all — `skills/team/SKILL.md:611-613`: *"CLI workers operate via tmux, not Claude Code's
  tool system. They cannot use Claude Code's native task-list or team messaging surfaces."* The
  lead's own responsibility, spelled out at `SKILL.md:602-607`: write a prompt file, spawn the
  pane, wait, then **read an output file** the worker is instructed to write, mark the task
  complete, and feed the result into any dependent task. A separate "Outbox Auto-Ingestion"
  mechanism (`SKILL.md:654-712`) lets the lead poll `readNewOutboxMessages()` /
  `readAllTeamOutboxMessages()` — a byte-offset-cursor file reader, explicitly described as
  mirroring the inbox-cursor pattern — to pull `task_complete`/`task_failed`/`idle`/`error`
  events out of the worker's outbox file without native message delivery.
- **The one-shot subprocess path** (`mcp-team-bridge.ts`) returns Codex's output as a plain string
  — the resolved value of the `result` promise in `spawnCliProcess()` — directly to its caller in
  the same process; no file relay needed since it's a synchronous-style `child_process` call.
- **`/ask codex`**'s output is written to `.omc/artifacts/ask/<provider>-<slug>-<timestamp>.md`
  (`skills/ask/SKILL.md:58-62`) — a durable file the calling session then reads, rather than a
  return value threaded through any call stack.

### 2.5 Fallback and error handling when Codex is unavailable or rate-limited

- **CLI absent from `PATH` at spawn time**: `validateCliAvailable()`
  (`src/team/model-contract.ts:381-389`) throws `` `CLI agent '${agentType}' not found.
  ${contract.installInstructions}` ``; the lower-level `getContract().buildLaunchArgs` path also
  throws `` `CLI binary '${binary}' not found in PATH` `` at two call sites
  (`model-contract.ts:123,129`). Detection itself is a real subprocess probe, not a config guess:
  `detectAllClis()` (`src/team/cli-detection.ts:281-291`) runs `codex --version` (via `detectCli`,
  which wraps a `spawnSync` version-check per `cli-detection.ts`'s `executeCliProbe`) and only
  reports a provider `available: true` if that check exits zero.
  `skills/team/SKILL.md:957-959` documents the resulting behavior in prose: *"If the CLI for a
  configured provider is absent from PATH at spawn time, `buildLaunchArgs()` throws, the team lead
  emits a visible team/conversation warning, and the runtime falls back to a deterministic Claude
  assignment pre-computed by `buildResolvedRoutingSnapshot` (same tier + same agent,
  `provider: "claude"`) only when the Claude CLI is resolvable. If the Claude CLI is unavailable,
  no runnable fallback exists... the warning stays loud rather than claiming a fallback."* The
  fallback pairing itself is pre-computed, not improvised at failure time:
  `buildResolvedRoutingSnapshot()` (`src/team/stage-router.ts:212-238`) resolves **every** role
  into a `{ primary, fallback }` pair up front, stripping any Codex-specific model id
  (`stage-router.ts:226-230`, comment: *"external model id... drop it for fallback so claude
  doesn't [inherit an invalid model name]"*) so the fallback assignment is always a valid Claude
  configuration.
- **Rate-limit / quota handling is Claude-side, not Codex-side.** The only rate-limit-aware
  subsystem found (`src/cli/commands/wait.ts`, `src/features/rate-limit-wait/`) is scoped to
  Claude's own OAuth-based usage limits (`wait.ts:88`: "Unable to check rate limits (OAuth
  credentials required)") — there is no equivalent Codex-quota detector or auto-resume daemon in
  the codebase; a rate-limited or quota-exhausted Codex CLI worker would surface as an ordinary
  task failure (reported by the worker via its inbox/outbox protocol) rather than a recognized,
  differently-handled condition. This is a real gap relative to matt-harness's own documented
  handling of the same failure mode (see §3).
- **Codex silently refusing an instruction** (the failure mode matt-harness's integration map
  calls out at length — see §3) has no equivalent handling found in oh-my-claudecode: nothing in
  `mcp-team-bridge.ts`'s `parseCodexOutput` or the tmux-pane path distinguishes a clean-exit,
  empty-diff refusal from a genuine no-op success.

### 2.6 Design rationale, in the repo's own words

- **Why tmux panes over `codex exec` for team workers**: the inline comment already quoted in
  §2.3 (`model-contract.ts:213-215`) is the only first-person rationale found; its logic is that
  team workers need to be long-lived, stateful participants (claim a task, work it, report,
  possibly pick up more work) rather than one-shot processes, which `codex exec`'s
  request-response shape doesn't fit — hence a persistent interactive pane plus a file-based
  inbox instead.
- **Why CLI-only over MCP for routing** (`resolver.ts`, `docs/MIGRATION.md:129-173`): no single
  paragraph states the "why" directly, but the pattern across both deprecations (per-role MCP
  provider routing, and the separate `omc_run_team_*` MCP runtime tools) is consistent with the
  comparison table `skills/team/SKILL.md:807-825` ("Team vs Legacy Swarm"), which frames the
  native-Claude-Code-team direction as removing a dependency (`better-sqlite3`), simplifying
  state (session task-list vs. a separate SQLite DB), and aligning with what Claude Code itself
  now provides natively (implicit agent teams as of Claude Code 2.1.178+) rather than maintaining
  a parallel MCP-server-based orchestration layer. The `/ccg` retirement note
  (`docs/MIGRATION.md:70`: `ccg` → `/oh-my-claudecode:ask` + `/team`, "Run `/ask codex` and `/ask
  antigravity`, then synthesize") points the same direction: multi-provider fan-out is now
  composed from the two CLI-first primitives (`ask`, `team`) rather than a dedicated
  MCP-orchestrated skill.
- **`docs/ARCHITECTURE.md:256-258`** documents a `ccg` (Claude-Codex-Gemini) *pattern* that "fans
  out to Codex and Antigravity simultaneously; Claude synthesizes the results" — this survives as
  a documented pattern even though the dedicated `/ccg` skill itself was retired
  (`docs/MIGRATION.md:54-70`) in the v5.0 workflow-retirement pass; the pattern is now something a
  lead composes from `/ask` + `/team` rather than a canned command.

---

## 3. Comparison to matt-harness's `docs/reference/codex-integration-map.md`

No changes proposed or made to matt-harness. This section is observation only.

### Where the two projects agree

- **Both treat the app-server as the serious integration point, not `codex mcp-server`.** mh's
  plugin drives the app-server directly (`codex-integration-map.md`'s sandbox note, `scripts/lib/codex.mjs`
  per the prior in-repo research note); OMC's own docs never mention `codex mcp-server` at all —
  its two Codex code paths are `codex exec` (one-shot) and a raw interactive `codex` TUI in a tmux
  pane, neither of which is the now-deprecated MCP-server mode. Both projects independently landed
  outside the deprecated surface without citing the deprecation notice — mh because it built on the
  app-server from the start, OMC because it never used MCP-server mode for Codex in the first
  place (its "MCP delegation" was routing tool calls through **OMC's own** MCP server, not Codex's).
- **Both use one-shot `codex exec --json` for the same shape of task**: a scoped, disposable,
  workspace-write verification pass. mh: compliance-audit Phase 2, "scoped to a disposable pinned
  worktree" (`codex-integration-map.md:19`). OMC: `mcp-team-bridge.ts`'s `spawnCliProcess`,
  `--dangerously-bypass-approvals-and-sandbox` (full access, not scoped by worktree — a real
  difference in blast-radius discipline, see below).
- **Both document the CLI-missing case as a named, non-silent fallback** rather than an
  undocumented crash: mh's "Degrading gracefully" section (`codex-integration-map.md:81-87`) says
  the routing table "just names an unavailable fallback path... the gate no-ops... check 71 reports
  INFO 'not installed'"; OMC's `buildLaunchArgs()`-throws-then-Claude-fallback story
  (§2.5 above) is the same shape of answer, independently engineered.

### Gaps and disagreements

- **Silent-refusal handling is mh-only.** matt-harness's integration map devotes an entire section
  ("Silent-refusal gotcha") to the fact that a Codex instruction-file default can make `codex exec`
  exit 0 with an empty diff and a polite refusal in the final message, and prescribes a concrete
  defense (compare `git status --porcelain` before/after, treat empty-diff-after-clean-run as
  `refused` never `complete`). **Nothing in oh-my-claudecode's Codex code paths checks for this.**
  Both `mcp-team-bridge.ts`'s `parseCodexOutput` and the tmux-pane worker path accept whatever
  Codex reports at face value. This is a real, concrete gap in a codebase that otherwise handles
  Codex-CLI absence carefully — worth naming as evidence the failure mode isn't obvious even to a
  team that has built extensive Codex tooling, not a reason for matt-harness to change anything
  (its own defense already exists and was validated live per the integration map's own evidence
  log).
- **Blast-radius discipline differs at the exact same call site.** mh's Phase-2 `codex exec`
  dispatch is deliberately "scoped to a disposable pinned worktree" even though it runs
  workspace-write. OMC's equivalent one-shot call (`mcp-team-bridge.ts:474`) and its persistent-pane
  worker (`model-contract.ts:218`) both pass `--dangerously-bypass-approvals-and-sandbox`
  unconditionally — full filesystem/network access, no worktree isolation visible in the read code.
  Team-worker git-worktree isolation *does* exist in OMC (`skills/team/SKILL.md:986-1018`,
  `createWorkerWorktree`/`mergeWorkerBranch`) but it's an opt-in feature for conflict prevention
  between concurrent workers, not a security/blast-radius boundary applied by default to every
  Codex dispatch the way mh's pinned-worktree pattern is. Worth noting as a design option mh could
  consider citing precedent for (it already does the stronger thing) rather than a gap mh has.
- **Rate-limit/quota awareness is asymmetric.** mh's plugin routing table explicitly names
  "rate-limit or absence" as a first-class fallback trigger for `/codex:review`,
  `/codex:adversarial-review`, and `/mh:compliance-audit`'s Phase 2
  (`codex-integration-map.md:13,14,19`). OMC has a whole rate-limit subsystem
  (`src/features/rate-limit-wait/`) — but it is Claude-only; no Codex-quota-specific detection
  exists in the reviewed code. A Codex rate-limit in OMC would present as an ordinary task failure,
  relying on the lead's generic "reassign or retry" handling rather than a recognized condition.
  This is an idea worth being aware of (a differently-shaped harness hit the same problem and did
  *not* solve it for Codex specifically) rather than something to act on.
- **The "who am I talking to" framing differs.** mh's map explicitly rejects being "a wrapper,
  mirror, or orchestration layer" for Codex (`codex-integration-map.md:3-5`) — Codex is a
  named, independent peer agent reached by explicit skill names. OMC's `/team` treats Codex as one
  of six *interchangeable* CLI-worker backends behind a uniform `CliAgentContract` interface
  (`model-contract.ts`), selected by a config value (`provider: "codex"`) the same way a build
  target might select a compiler. Neither framing is wrong; they reflect different goals (mh: two
  named agents cross-checking each other; OMC: N workers of a configurable species doing the same
  kind of task). This is the single largest structural disagreement between the two projects and
  is presented here as a fact, not a recommendation to change either one.
- **New fact for mh to be aware of, not a gap**: today's confirmation that `codex mcp-server` is
  now officially deprecated (§1.3) is upstream news, not something either project got wrong — it
  simply didn't exist as a documented fact yesterday. It reinforces, with an official citation,
  that mh's app-server-based plugin architecture is aligned with Codex's current recommended
  integration surface rather than a surface OpenAI is walking back.

---

## Sources

**Official (OpenAI), fetched today (2026-09-07) unless noted:**
- https://developers.openai.com/codex/auth.md → https://learn.chatgpt.com/docs/auth.md (auth methods)
- https://developers.openai.com/codex/auth/ci-cd-auth → https://learn.chatgpt.com/docs/auth/ci-cd-auth.md (CI auth persistence)
- https://developers.openai.com/codex/pricing → https://learn.chatgpt.com/docs/pricing (rate limits)
- https://learn.chatgpt.com/docs/mcp-server (MCP server mode + deprecation notice)
- https://developers.openai.com/codex/noninteractive → https://learn.chatgpt.com/docs/non-interactive-mode.md (`codex exec` flags/output/sessions)
- https://raw.githubusercontent.com/openai/codex/main/README.md
- `gh api repos/openai/codex` and `gh api repos/openai/codex/releases/latest`
- local `codex --version` (codex-cli 0.153.4)

**Reused, not re-fetched today, from `docs/research/native-tools-claude-code-vs-codex-2026-09-06.md`**
(this repo, 2026-09-06, itself sourced to `learn.chatgpt.com/docs/app-server`,
`learn.chatgpt.com/docs/sandboxing`, `learn.chatgpt.com/docs/config-file/config-reference`, and
`codex --help`/`codex exec --help`): the app-server's JSON-RPC method surface, and the
approval-policy behavioral descriptions inside §1.2 (mode names were re-confirmed today; behavior
text was not re-shown on today's fetch).

**Secondary, flagged as such, not treated as authoritative:**
- DeepWiki `openai/codex` wiki pages on MCP-server implementation and session resumption
  (AI-generated third-party wiki, used only to explain *why* the app-server is now preferred,
  a claim the official deprecation notice already independently establishes).

**Local repo, read directly (`~/Codes/Personals/oh-my-claudecode`, no edits made):**
`src/features/delegation-routing/resolver.ts`, `src/team/model-contract.ts`,
`src/team/mcp-team-bridge.ts`, `src/team/worker-bootstrap.ts`, `src/team/cli-detection.ts`,
`src/team/stage-router.ts`, `src/cli/ask.ts`, `src/cli/team.ts`, `src/cli/commands/team.ts`,
`src/cli/commands/wait.ts`, `skills/team/SKILL.md`, `skills/ask/SKILL.md`, `docs/MIGRATION.md`,
`docs/ARCHITECTURE.md`.

**In-repo (matt-harness):** `docs/reference/codex-integration-map.md`, `docs/adr/0001-gate-codex-setup-not-rescue.md`,
`docs/research/native-tools-claude-code-vs-codex-2026-09-06.md`, `docs/research/delegation-criteria-field-survey-2026-09-04.md` (structure/tone reference only).
