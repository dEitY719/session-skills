# Agent Detection -- priority chain and environment variables

## Detection Priority

Determine `agent_name` using this order (first match wins):

1. `--ai <name>` argument (if user provided)
2. `$AI_AGENT_NAME` environment variable
3. Agent-specific env vars (see table below)
4. Fallback: `agent`

## Per-Agent Environment Variables

| AI Agent | Detection Method | Result Name |
|---|---|---|
| Claude Code | `$CLAUDECODE == 1` | `claude` |
| Antigravity CLI | `$AGY_CLI == 1` or process name `agy` | `agy` |
| Codex CLI | `$CODEX_CLI == 1` or process name `codex` | `codex` |
| OpenCode | `$OPENCODE == 1` or `~/.opencode/` exists | `opencode` |
| Cursor | `$CURSOR == 1` or `$TERM_PROGRAM == cursor` | `cursor` |
| Copilot | `$GITHUB_COPILOT == 1` | `copilot` |

Environment variable names may change across tool versions. The detection logic
is isolated in `detect_ai_agent()` for easy extension.
