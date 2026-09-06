#!/usr/bin/env bash
# 72. Codex effort-set drift: docs/reference/spawn-brief.md names the
# `--effort <a|b|c>` set the paired codex@openai-codex plugin validates
# (VALID_REASONING_EFFORTS in its codex-companion.mjs). The plugin updates on
# its own clock, so WARN when the two sets differ; INFO and fail-open when
# either side is missing -- this reads third-party operator-machine state.
_codex_cache="${MH_CODEX_CACHE_DIR:-}"
if [ -z "$_codex_cache" ]; then
  _codex_cache=$(for _codex_dir in "$HOME"/.claude/plugins/cache/openai-codex/codex/*/; do if [ -d "$_codex_dir" ]; then printf '%s\n' "$_codex_dir"; fi; done | sort -V | tail -1)
fi
_codex_doc="$REPO_ROOT/docs/reference/spawn-brief.md"
_codex_companion="${_codex_cache%/}/scripts/codex-companion.mjs"
if [ -z "$_codex_cache" ] || [ ! -f "$_codex_companion" ]; then
  info "codex@openai-codex not installed (no codex-companion.mjs) -- effort-set drift check skipped"
elif [ ! -f "$_codex_doc" ]; then
  info "docs/reference/spawn-brief.md missing -- effort-set drift check skipped"
else
  _codex_plugin_set=$(sed -n 's/.*VALID_REASONING_EFFORTS = new Set(\[\(.*\)\]).*/\1/p' "$_codex_companion" | head -1 | tr -d "\"' " | tr ',' '\n' | sed '/^$/d' | sort | tr '\n' ' ')
  _codex_doc_set=$(sed -n 's/.*--effort <\([a-z|]*\)>.*/\1/p' "$_codex_doc" | head -1 | tr '|' '\n' | sort | tr '\n' ' ')
  if [ -z "$_codex_plugin_set" ]; then
    info "VALID_REASONING_EFFORTS not found in $_codex_companion -- plugin layout changed; update check 72"
  elif [ -z "$_codex_doc_set" ]; then
    warn "docs/reference/spawn-brief.md has no '--effort <a|b|c>' set to compare against the paired Codex plugin"
  elif [ "$_codex_plugin_set" != "$_codex_doc_set" ]; then
    warn "Codex effort set drifted: spawn-brief.md says [${_codex_doc_set% }], installed plugin validates [${_codex_plugin_set% }] ($_codex_companion) -- update the doc"
  else
    info "Codex effort set in spawn-brief.md matches the installed plugin [${_codex_plugin_set% }]"
  fi
  unset _codex_plugin_set _codex_doc_set
fi
unset _codex_cache _codex_doc _codex_companion
