# Native tool sets: Claude Code vs OpenAI Codex CLI

Date: 2026-09-06. Method: official docs only (`code.claude.com/docs/en/*`; `developers.openai.com/codex/*`,
which now 308-redirects to `learn.chatgpt.com/docs/*`), context7 over `/openai/codex` and `/websites/code_claude`,
plus local ground truth: `claude --version` = 2.1.263, `codex --version` = codex-cli 0.153.4, `strings` on
`$HOME/.local/share/claude/versions/2.1.263`, `codex --help` / `codex exec --help` / `codex features list`, and the
installed `codex@openai-codex` plugin at `$HOME/.claude/plugins/cache/openai-codex/codex/1.0.6/`.
Source: prior-note check via `qmd` over `llm-wiki` + `mh-research` returned no note on this question (hits were
third-party plugin write-ups, none reused). Where mh already covers a point, this note links
`docs/reference/codex-integration-map.md` instead of repeating it.

## TL;DR

- Claude Code exposes ~45 named built-in tools (file, search, shell, web, orchestration, tasks, cron, MCP
  helpers); Codex exposes a handful the docs name only as feature flags (`shell_tool`/`unified_exec`,
  `apply_patch`, `web_search`, `view_image`, `image_generation`, `request_permissions`) and does not publish a
  tool-by-tool reference page.
- Both gate work the same two ways, with different vocab: Claude Code = permission rules (`deny` > `ask` >
  `allow`) + permission modes + optional OS sandbox for Bash; Codex = `sandbox_mode` (OS-enforced, always on by
  default) + `approval_policy` (`untrusted` | `on-request` | `never`, `on-failure` deprecated).
- Same OS primitives on both sides: Seatbelt on macOS, bubblewrap on Linux/WSL2 (Claude Code adds `socat` +
  optional seccomp; Codex adds Landlock). Neither sandboxes native Windows.
- Claude Code's sandbox is opt-in (`sandbox.enabled`, default off) and covers only Bash; Codex's sandbox is
  the default execution boundary and covers every model-run command. `codex exec` defaults to `read-only`.
- The `codex@openai-codex` plugin bypasses `config.toml`: it sends `approvalPolicy: "never"` and an explicit
  `sandbox` (`read-only` for review, caller-set for rescue) on every `thread/start` via the app-server.
- Extension surfaces now line up almost 1:1: both have MCP, skills (agentskills.io standard), hooks (Codex
  shipped `PreToolUse`/`PermissionRequest` etc. with the same names), and plugins. The real asymmetry is
  instruction files (`AGENTS.md` vs `CLAUDE.md`) and config precedence (Codex project config is *lowest*).
- For mh the material differences are: Codex hooks exist but mh's `gate:*` hooks are Claude Code hooks; a
  Codex `never` policy makes silent refusals the failure mode; and `--add-dir` / `writableRoots` is the
  supported way to widen writes, never `danger-full-access`.

## 1. Claude Code native tools

Permission column follows the official tools reference table ("Permission Required" in Manual mode). In auto
mode a classifier resolves most prompts; file tools still prompt outside the working directory
(https://code.claude.com/docs/en/tools-reference). Rule syntax `ToolName(specifier)`; evaluation order is
deny, then ask, then allow, first match wins, specificity does not reorder
(https://code.claude.com/docs/en/permissions, "Rules are evaluated in order: deny, then ask, then allow").

| Tool | Purpose | Key params | Permission gate | Sandbox / notes |
|---|---|---|---|---|
| `Bash` | Shell commands | `command`, `timeout`, `run_in_background` | Yes, except built-in read-only command set; `Bash(npm run *)` rules | Only tool the OS sandbox wraps; 2 min default / 10 min max timeout; 30k chars inline output |
| `PowerShell` | Native PowerShell | `command`, `timeout` | Yes | Windows default; opt-in elsewhere (`CLAUDE_CODE_USE_POWERSHELL_TOOL`) |
| `Read` | Read file / image / PDF / notebook | `offset`, `limit`, `pages` | No inside working dir; prompts outside | `Read(./.env)` deny rules; PDFs >10 pages need `pages` |
| `Edit` | Exact-string replace | `old_string`, `new_string`, `replace_all` | Yes; `Edit(/src/**)` | Read-before-edit; an `Edit` allow also grants read on that path |
| `Write` | Create/overwrite file | path, content | Yes | Same path-rule syntax as Edit |
| `NotebookEdit` | Edit Jupyter cells | `cell_id`, `cell_type`, mode | Yes | |
| `Glob` / `Grep` | File pattern / ripgrep search | `pattern`, `path`, `glob`, `type`, `multiline` | No (in working dir) | Grep respects `.gitignore` |
| `LSP` | Definitions/references/types | file, position, action | No | Needs a code-intelligence plugin |
| `WebFetch` | Fetch URL, extract via prompt | `url`, prompt | Yes, except preapproved doc domains; `WebFetch(domain:x)` | Lossy (HTML to Markdown); 15 min cache; cross-host redirects returned, not followed |
| `WebSearch` | Web search | query | Yes; bare `WebSearch` rule only | |
| `Agent` | Spawn subagent (own context) | `name`, `maxTurns`, `tools`, `disallowedTools` | No; `Agent(Explore)`, `Agent(model:opus)` rules | `disallowedTools` wins when both set; zero-match set errors instead of spawning |
| `Skill` | Run a skill | name, args | Yes; `Skill(deploy *)` | `disable-model-invocation` blocks model calls outright |
| `AskUserQuestion` | Multiple-choice clarification | options | No | Denied in `dontAsk` mode even if allowed |
| `ToolSearch` | Load deferred tools (MCP, some built-ins) | query | No | Tool search on by default since v2.1.221 |
| `TaskCreate/Get/List/Update`, `TodoWrite` | Session task list | task fields | No | Off by default on Opus 4.8 / Sonnet 5 / Fable 5+; opt in with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` |
| `TaskStop`, `TaskOutput` | Stop / read a background task | id | No | `TaskOutput` deprecated |
| `Monitor` | Background command or WebSocket feed | `command` or `ws`, `timeout_ms` | Yes (classifier treats like Bash) | Denies private/link-local/metadata addresses |
| `EnterPlanMode` / `ExitPlanMode` | Plan mode toggle | – | No / Yes | |
| `EnterWorktree` / `ExitWorktree` | Isolated git worktree | `path` | Yes / No | |
| `SendMessage`, `ListAgents` | Cross-session / teammate messaging | target, message | No | v2.1.224+ |
| `CronCreate/Delete/List`, `ScheduleWakeup`, `RemoteTrigger` | Scheduling, `/loop`, claude.ai Routines | schedule, prompt | No | `RemoteTrigger` absent on Bedrock/Vertex/Foundry |
| `ListMcpResourcesTool`, `ReadMcpResourceTool`, `WaitForMcpServers` | MCP resources | server, URI | No | |
| `Artifact`, `SendUserFile`, `PushNotification`, `ShareOnboardingGuide`, `SendFeedback` | Publish page / send file / notify | content, paths | Artifact + ShareOnboardingGuide: Yes; rest No | Plan-gated (Pro/Max/Team/Enterprise) |
| `Workflow` | Dynamic subagent orchestration script | script | Yes | |
| `EndConversation` | End session on sustained abuse | – | No; cannot be denied | v2.1.213+, Opus 4.8+, interactive only |

Source for every row: https://code.claude.com/docs/en/tools-reference ("Complete Tool List" table plus the per-tool
behaviour sections). Binary cross-check: `strings` on `$HOME/.local/share/claude/versions/2.1.263` matches the
quoted names `"Bash"`, `"Read"`, `"Edit"`, `"Write"`, `"Agent"`, `"Skill"`, `"Grep"`, `"Glob"`, `"WebFetch"`,
`"WebSearch"`, `"Monitor"`, `"ToolSearch"`, `"CronCreate"`, `"EnterWorktree"`, `"Workflow"`, `"Artifact"`, and also
`"Task"`, `"MultiEdit"`, `"LS"`, `"BashOutput"`, `"KillShell"`, `"TeamCreate"`, `"Sleep"` (the last group are
legacy/undocumented; see section 6).

Permission modes (https://code.claude.com/docs/en/permissions, "Permission modes" table): `default` (Manual),
`acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`. `bypassPermissions` also skips writes to
protected paths such as `.git` and `.claude`; `permissions.disableBypassPermissionsMode` / `disableAutoMode`
turn those modes off, most usefully from managed settings.

Bash sandbox (https://code.claude.com/docs/en/sandboxing): opt-in via `/sandbox` or `sandbox.enabled`; macOS
Seatbelt, Linux/WSL2 `bubblewrap` + `socat` + optional seccomp filter (`@anthropic-ai/sandbox-runtime`); no
native Windows. Default writable set: working directory, session temp dir (`$TMPDIR` rewritten), and
`--add-dir` / `permissions.additionalDirectories`; `sandbox.filesystem.allowWrite/denyWrite/denyRead/allowRead`
widen or narrow it. Default read scope is the whole machine except denied dirs (credential files stay readable
unless `sandbox.credentials` or `denyRead` covers them). Network goes through a proxy with zero pre-allowed
domains; approving a host "don't ask again" writes a `WebFetch(domain:...)` allow rule. Auto-allow runs
sandboxed commands without prompting even in Manual mode (`autoAllowBashIfSandboxed` default `true`); commands
that cannot be sandboxed fall back to the normal prompt titled "Bash command (unsandboxed)", and
`allowUnsandboxedCommands: false` removes that escape hatch. If the sandbox cannot start it warns and runs
unsandboxed unless `sandbox.failIfUnavailable` is `true`. In a linked worktree the shared `.git` is writable
except `hooks/` and `config`.

## 2. Codex CLI native tools

Codex has no per-tool reference page; the tools surface as feature flags in the config reference and CLI help.
Names below are the flag/tool names the official sources use.

| Tool / flag | Purpose | Key params / values | Approval gate | Source |
|---|---|---|---|---|
| `shell_tool` (`features.shell_tool`, stable, on) | Model-run shell commands | command, cwd; `allow_login_shell` governs login shells | Sandbox first; escalation follows `approval_policy` | `codex features list` = "shell_tool stable true"; config-reference `allow_login_shell` |
| `unified_exec` (`features.unified_exec`, stable, on except Windows) | PTY-backed exec replacing the plain shell tool | stdin writes, background sessions (`/ps`, `/stop`) | Same as shell | config-reference: "Use the unified PTY-backed exec tool (stable; enabled by default except on Windows)"; app-server `feature/list` entry `unified_exec` |
| `apply_patch` | File edits as a patch | patch text | Write needs `workspace-write` or approval; `item/fileChange/requestApproval` on app-server | `codex features list` shows `apply_patch_*` sub-flags; app-server approval flow (https://learn.chatgpt.com/docs/app-server) |
| `web_search` | Web search | top-level `web_search = disabled \| cached \| indexed \| live`, default `cached`; `--search` enables live | "no per-call approval" | `codex --help` `--search` text; config-reference `web_search` |
| `view_image` (`features.view_image`, stable, on) | Attach a local image to context | path | none documented | config-reference: "Enable the local-image attachment tool `view_image`" |
| `image_generation` (stable, on) | Generate images | – | none documented | `codex features list` |
| `request_permissions` (`request_permissions_tool`, under development, off) | Ask for a subset of network/filesystem grants | permissions set | `item/permissions/requestApproval` server request; `approval_policy.granular.request_permissions` | app-server doc; config-reference `approval_policy` type |
| Subagents (`multi_agent`, stable, on) | `spawn_agent`, `send_message`, `wait_agent`, `close_agent` | – | inherits thread policy | `codex features list`; codex-rs `rollout-trace/src/tool_dispatch.rs` names via context7 |
| MCP tools | External servers | `mcp_servers.<id>` | `default_tools_approval_mode = auto \| prompt \| writes \| approve`, per-tool `tools.<tool>.approval_mode` | https://learn.chatgpt.com/docs/extend/mcp |

Sandbox modes (`sandbox_mode`, `--sandbox`/`-s`): `read-only` ("can inspect files, but it can't edit files or
run commands without approval"), `workspace-write` ("the default low-friction mode for local work"),
`danger-full-access` (removes filesystem and network boundaries). Source: https://learn.chatgpt.com/docs/sandboxing
"Configure defaults"; values also in `codex --help`. `workspace-write` extras: `sandbox_workspace_write.writable_roots`,
`.network_access` (bool, off by default), `.exclude_tmpdir_env_var`, `.exclude_slash_tmp` (so `/tmp` and `$TMPDIR`
are writable unless excluded) (https://learn.chatgpt.com/docs/config-file/config-reference). CLI: `--add-dir` adds
writable dirs; the CLI reference says to prefer it over `danger-full-access`
(https://learn.chatgpt.com/docs/developer-commands.md?surface=cli). OS: Seatbelt on macOS, `bubblewrap` +
Landlock on Linux/WSL2, Windows via its own sandbox setup (`windowsSandbox/setupStart` in app-server; `codex sandbox`
help says "run under seatbelt"). The app-server adds `externalSandbox` for containers and restricted
`readableRoots` on `readOnly`/`workspaceWrite` (https://learn.chatgpt.com/docs/app-server, "Sandbox read access").

Approval policies (`approval_policy`, `--ask-for-approval`/`-a`): `untrusted` (ask before commands outside the
trusted set), `on-request` (model asks when it must leave the sandbox), `never` (no prompts; failures go back to
the model), plus a `{ granular = { sandbox_approval, rules, mcp_elicitations, request_permissions, skill_approval } }`
table; `on-failure` is deprecated (config-reference `approval_policy` type + description). `codex --help` only
lists `on-request` and `never` for `-a`. `approvals_reviewer = user | auto_review` picks who answers prompts
under `on-request`. Presets: full access = `danger-full-access` + `never`; the documented low-risk automation
preset is `workspace-write` + `on-request` (sandboxing page). `--dangerously-bypass-approvals-and-sandbox` = full
access + never (`codex --help`); `--full-auto` is deprecated and prints a warning
(https://learn.chatgpt.com/docs/non-interactive-mode).

`codex exec`: read-only sandbox by default, progress to stderr, final message to stdout, `--json` JSONL events
(`thread.started`, `turn.completed`, `item.completed`, `error`), `-o/--output-last-message`, `--output-schema`,
`--ephemeral`, `--skip-git-repo-check`, `--ignore-user-config`, `--ignore-rules`, `resume`/`fork`/`review`
subcommands (https://learn.chatgpt.com/docs/non-interactive-mode; `codex exec --help`).

App-server: JSON-RPC 2.0 over stdio/WebSocket/Unix socket; `thread/start`, `thread/resume`, `thread/fork`,
`turn/start`, `turn/steer`, `turn/interrupt`, `review/start`; per-turn overrides for `model`, `effort`, `cwd`,
`sandboxPolicy`, `approvalPolicy` that persist as thread defaults; approvals arrive as
`item/commandExecution/requestApproval` / `item/fileChange/requestApproval`; `thread/shellCommand` and
`command/exec` run *outside* the thread sandbox and are meant for user-initiated commands only
(https://learn.chatgpt.com/docs/app-server). `codex mcp-server` exposes Codex itself over MCP stdio
(`codex --help`).

## 3. Extension surfaces side by side

| Surface | Claude Code | Codex CLI |
|---|---|---|
| MCP | `claude mcp add`, scopes local (`~/.claude.json`) / project (`.mcp.json`) / user; stdio, http, sse (deprecated), ws; tools named `mcp__<server>__<tool>`; permission rules by tool pattern; deferred loading via ToolSearch (https://code.claude.com/docs/en/mcp) | `[mcp_servers.<id>]` in `~/.codex/config.toml` or `.codex/config.toml`; stdio + streamable HTTP; `enabled_tools`/`disabled_tools`; `default_tools_approval_mode`; `codex mcp add/list` (https://learn.chatgpt.com/docs/extend/mcp) |
| Hooks | Events incl. `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SubagentStart/Stop`, `PreCompact`, `SessionStart`; `permissionDecision: allow\|ask\|deny`, `updatedInput`; exit 2 blocks, exit 1 does not; types command/http/mcp_tool/prompt/agent; plugin `hooks/hooks.json` merges with settings (https://code.claude.com/docs/en/hooks) | Events `SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`; `~/.codex/hooks.json` or `[hooks]` in config; persisted hook trust keyed by hash, `--dangerously-bypass-hook-trust`; `PreToolUse` can deny or rewrite input (https://learn.chatgpt.com/docs/hooks; `features.hooks` stable on) |
| Skills | `SKILL.md` in `~/.claude/skills`, `.claude/skills`, plugins, enterprise; Claude-only frontmatter `disable-model-invocation`, `user-invocable`, `context: fork`, `allowed-tools`, `effort`; agentskills.io standard (https://code.claude.com/docs/en/skills) | `SKILL.md` in `.agents/skills` (repo, walking up), `$HOME/.agents/skills`, `/etc/codex/skills`, bundled; `$skill` explicit or implicit; `agents/openai.yaml` optional; same agentskills.io standard; `approval_policy.granular.skill_approval` (https://learn.chatgpt.com/docs/build-skills) |
| Plugins | `.claude-plugin/plugin.json`; `skills/`, `agents/`, `hooks/`, `.mcp.json`, `.lsp.json`, `monitors/`, `bin/`; namespaced `/plugin:skill`; cache under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` (https://code.claude.com/docs/en/plugins) | `codex plugin` subcommand, `/plugins`; `plugins.<plugin>.mcp_servers.<server>.*` config keys (`codex --help`; config-reference) |
| Instruction files | `CLAUDE.md` chain (managed, `~/.claude/CLAUDE.md`, project, `CLAUDE.local.md`, subdir lazy, `.claude/rules/`), `@import`; reads `CLAUDE.md` not `AGENTS.md`, docs suggest `@AGENTS.md` import or symlink (https://code.claude.com/docs/en/memory) | `~/.codex/AGENTS.override.md` else `~/.codex/AGENTS.md`, then git root down to cwd, one file per dir, concatenated root-first, stop at `project_doc_max_bytes` (32 KiB default); `project_doc_fallback_filenames` (https://learn.chatgpt.com/docs/agent-configuration/agents-md) |
| Config precedence | Managed > `--settings` CLI > `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json` (https://code.claude.com/docs/en/settings) | CLI flags > `--profile` file > `~/.codex/config.toml` > built-in defaults > project `.codex/config.toml` (lowest; cannot set provider/auth/telemetry keys) (config-reference "Configuration Precedence Order") |
| Non-interactive | `claude -p`, `--tools`, `--allowedTools`, `--permission-mode` (cli-reference via context7) | `codex exec`, `--json`, `--output-schema`, app-server, `codex mcp-server` |

## 4. Differences that matter for mh

- **Sandbox default polarity.** Codex sandboxes every model command by default; Claude Code sandboxes only
  Bash and only when `sandbox.enabled`. Implication: a rescue run under Codex is *more* contained at the OS level
  than the same edit under mh, while mh's containment lives in `gate:*` PreToolUse hooks. The integration map's
  "Gate gap" section already records that those gates never see app-server writes.
- **Plugin bypasses config.toml.** `scripts/lib/codex.mjs` `buildThreadParams` sends `approvalPolicy: options.approvalPolicy ?? "never"`
  and `sandbox: options.sandbox ?? "read-only"`; `runAppServerReview` hardcodes `sandbox: "read-only"`;
  `runAppServerTurn` passes the caller's `options.sandbox` and `effort` on `turn/start`. Implication: a user's
  `~/.codex/config.toml` `sandbox_mode`/`approval_policy` does not govern plugin runs (already stated in the
  integration map's sandbox note); `hooks`, `mcp_servers`, `AGENTS.md`, and `project_doc_max_bytes` still do.
- **`never` makes refusal silent.** With `approvalPolicy: never`, an escalation the sandbox would have asked
  about is returned to the model as a failure, and an instruction-file refusal exits 0 with an empty diff.
  Implication: the empty-diff check in the integration map's "Silent-refusal gotcha" is the only reliable signal;
  do not read exit 0 as done.
- **Codex has hooks now, same event names.** `PreToolUse`/`PermissionRequest` in `~/.codex/hooks.json` with
  persisted trust. Implication: if mh ever wants a Codex-side floor above git hooks, the surface exists; a port
  of `gate:bash:irrecoverable` would be a Codex `PreToolUse` deny, not an AGENTS.md sentence. Not needed for the
  current trial (ADR-0001 keeps rescue ungated).
- **Widening writes.** Codex's supported knob is `--add-dir` / `sandboxPolicy.writableRoots`; the CLI reference
  says to prefer it over `danger-full-access`. Implication: a rescue that must touch a sibling dir should pass
  writable roots, never escalate the mode; the plugin's `workspace-write` ceiling stays.
- **Instruction-file loading is unconditional and size-capped on Codex.** Global `AGENTS.md` always loads;
  the chain stops at 32 KiB. Implication: the AGENTS.md paragraph in the integration map must stay short, and a
  long root `AGENTS.md` can starve nested ones silently.
- **Config precedence is inverted at the project level.** Codex project `.codex/config.toml` is the *lowest*
  layer; Claude Code project settings sit above user settings. Implication: mh cannot ship a repo-level
  `.codex/config.toml` that overrides a user's sandbox choice; only the plugin's structured params do that.
- **`--tools` vs feature flags.** Claude Code narrows the built-in set per invocation (`claude --tools "Bash,Edit,Read"`);
  Codex narrows by `--disable <feature>` / `features.*`. Implication: a read-only Codex review is enforced by
  `sandbox: read-only`, not by removing `apply_patch`, so the model can still *emit* patches that fail.
- **Skills format is shared, locations are not.** Both follow agentskills.io, but Codex reads `.agents/skills`
  and Claude Code reads `.claude/skills`; Claude-only frontmatter (`disable-model-invocation`, `context: fork`)
  is ignored by Codex. Implication: a skill mh wants both agents to see needs a copy or symlink, and its gating
  cannot ride on frontmatter.

## 5. Sources reused from local knowledge

None. `qmd` hits over `llm-wiki` and `mh-research` were third-party plugin write-ups (ECC, oh-my-claudecode,
Medium-style guides); none met the official-source bar.

## 6. Unverified / not found in official docs

- Claude Code binary strings `"Task"`, `"MultiEdit"`, `"LS"`, `"BashOutput"`, `"KillShell"`, `"TeamCreate"`,
  `"TeamDelete"`, `"Sleep"`, `"Config"` (2.1.263) have no row in the tools reference; treat as legacy aliases or
  internal names, not documented tools.
- Codex tool names `exec_command`, `local_shell`, `shell_command`, `write_stdin`, `spawn_agent`, `wait_agent`,
  `close_agent` come from codex-rs source (`rollout-trace/src/tool_dispatch.rs` via context7), not from a docs
  page. Official docs name only the feature flags.
- Codex `on-failure` approval value: documented only as deprecated in the config reference; the sandboxing page
  omits it entirely.
- Claude Code `--tools` / `--allowedTools` flags: seen via context7's cli-reference excerpt, not fetched directly.
- Codex `.git` / `.codex` write protection under `workspace-write`: the sandboxing page does not spell this out;
  the app-server doc only shows `writableRoots`. Not asserted above.
- `codex mcp-server` tool names (`codex`, `codex-reply`): not in the fetched MCP page; only the subcommand's
  existence is cited.
