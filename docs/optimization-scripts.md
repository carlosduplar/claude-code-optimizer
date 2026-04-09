# Optimization Scripts

This project configures Claude Code using a single file:

- `~/.claude/settings.json`

## Requirements

- **Windows**: PowerShell 7.0+ (uses `-AsHashtable`)
- **Linux/macOS**: Bash

## Profiles

- `official`: official-docs-aligned baseline
- `tuned`: official baseline plus reverse-engineered tuning overlay (default)

## Optimizer flags

### Linux / macOS / WSL

```bash
./scripts/linux/optimize-claude.sh \
  --profile tuned \
  --privacy max
```

### Windows

```powershell
.\scripts\windows\optimize-claude.ps1 `
  -Profile tuned `
  -Privacy max
```

### Common options

- `--profile official|tuned`
- `--privacy standard|max` (default: `max`)
- `--unsafe-auto-approve` (broad Bash allowlist; high risk)
- `--auto-format`
- `--dry-run`
- `--skip-deps`
- `--verify`

## Safety defaults

- `Read` preprocessing is non-mutating (temp artifacts + `updatedInput` redirection)
- default Bash auto-approve is limited to conservative read-only metadata commands
- high-risk content-read commands are only enabled with `--unsafe-auto-approve`
- keepalive is reminder-based (SessionStart), not fake PostToolUse hook output
- user `permissions.allow` entries are merged and deduplicated (not overwritten)

## Notes

- Use `--profile official` to disable reverse-engineered tuning.
- Use `--unsafe-auto-approve` only in trusted isolated environments.
