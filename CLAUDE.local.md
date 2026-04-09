# Claude Code Optimizer - Project Instructions

## Critical Rule: Consult Documentation First

Before implementing ANY optimization or feature, you MUST consult the Claude Code official documentation in `raw/`.

The `raw/` directory contains a local mirror of all Claude Code documentation. Most previous optimizations were incorrect because they assumed behavior rather than reading the actual docs.

## Required Workflow

1. **Identify the relevant docs**: Look in `raw/en/` for the feature area you're modifying
2. **Read the documentation**: Use the Read tool on relevant markdown files in `raw/`
3. **Verify your approach**: Ensure your implementation matches documented behavior
4. **Then implement**: Only after confirming with official docs

## Common Doc Locations

- `raw/en/settings.md` - Configuration, hooks, permissions
- `raw/en/permissions.md` - Auto-approval, permissions.allow patterns
- `raw/en/hooks.md` - Hook events, matchers, exit codes
- `raw/en/output-styles.md` - Output styles vs CLAUDE.md distinction
- `raw/en/commands.md` - Built-in slash commands

## Examples of Previous Failures

- Auto-approve via hooks (wrong - use settings.json permissions.allow)
- CAVEMAN mode naming (conflicted with official output styles)
- Hook-based permission overrides (hooks cannot override permissions)

When in doubt, read the docs first.
