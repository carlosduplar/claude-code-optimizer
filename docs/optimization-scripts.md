# Optimization Scripts v1.0.0

> Last verified against official docs: 2026-11-08. `promptCacheTtl` requires CLI v2.1.242+. Output-style switching requires v2.1.251+ (mid-session) / v2.1.269+ (CLI).

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
- `--output-style caveman|caveman-ultra|none` (default: `caveman`)
- `--unsafe-auto-approve` (broad Bash allowlist; high risk)
- `--auto-format` (off by default, opt-in)
- `--dry-run`
- `--skip-deps`
- `--verify`

## Safety defaults

- `Read` preprocessing is non-mutating (temp artifacts + `updatedInput` redirection)
- default Bash auto-approve is limited to conservative read-only metadata commands
- high-risk content-read commands are only enabled with `--unsafe-auto-approve`
- keepalive is reminder-based (`SessionStart` startup only); no fake cache-keepalive hook output
- user `permissions.allow` entries are merged and deduplicated (not overwritten)
- output styles installed from `assets/output-styles/` (caveman-output-style v1.2.0); active style via `outputStyle` (lowercase, case-sensitive)

## Notes

- Use `--profile official` to disable reverse-engineered tuning.
- Use `--unsafe-auto-approve` only in trusted isolated environments.
