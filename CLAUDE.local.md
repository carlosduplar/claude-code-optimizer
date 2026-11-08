# Claude Code Optimizer - Project Instructions

## Critical Rule: Consult Documentation First

Before implementing ANY optimization or feature, you MUST consult the official Claude Code documentation at https://code.claude.com/docs/en/.

There is no vendored `raw/` mirror in this repo (removed). Use `webfetch` on the official docs URLs. Most previous optimizations were incorrect because they assumed behavior rather than reading the actual docs.

## Required Workflow

1. **Identify the relevant docs**: `settings`, `permissions`, `hooks`, `output-styles`, `prompt-caching`, `memory`, `env-vars` under https://code.claude.com/docs/en/
2. **Read the documentation**: Use webfetch on the official pages; pin the Claude Code version you verified against
3. **Verify your approach**: Ensure your implementation matches documented behavior
4. **Label confidence**: Tag all technical claims as HIGH/MEDIUM/LOW/UNKNOWN per CLAUDE.md
5. **Then implement**: Only after confirming with official docs

## Common Doc Locations

- https://code.claude.com/docs/en/settings — Configuration, hooks, permissions
- https://code.claude.com/docs/en/permissions — Auto-approval, permissions.allow patterns
- https://code.claude.com/docs/en/hooks — Hook events, matchers, exit codes
- https://code.claude.com/docs/en/output-styles — Output styles vs CLAUDE.md distinction
- https://code.claude.com/docs/en/prompt-caching — Cache TTL, promptCacheTtl, invalidation
- https://code.claude.com/docs/en/memory — CLAUDE.md, auto memory, rules
- https://code.claude.com/docs/en/env-vars — Environment variables reference

## Examples of Previous Failures

- Auto-approve via hooks (wrong - use settings.json permissions.allow)
- CAVEMAN mode naming (conflicted with official output styles) — fixed: source of truth is `caveman-output-style-claude-code` repo, assets/output-styles/
- Hook-based permission overrides (hooks cannot override permissions)
- Stale `ENABLE_PROMPT_CACHING_1H`-only caching (canonical is now `promptCacheTtl: 1h`)
- Old caveman heredoc drift (fixed: installers copy from assets/)

When in doubt, read the docs first.
