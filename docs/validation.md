# Validation

Validation now checks only `~/.claude/settings.json`.

## Run

### Linux / macOS / WSL

```bash
./scripts/linux/validate.sh --profile tuned --privacy max
```

### Windows

```powershell
.\scripts\windows\validate.ps1 -Profile tuned -Privacy max
```

## Optional assertions

- Linux: `--expect-unsafe`
- Windows: `-ExpectUnsafe`

Use these only when optimizer was run with unsafe broad auto-approve enabled.

## What is validated

- schema presence
- env object presence
- PreToolUse and SessionStart hooks configured
- permissions deny list configured
- profile-specific tuning keys
- privacy-specific keys
- unsafe allowlist presence/absence

## Keepalive behavior

Validation does not assert fake `cache_keepalive` hook output. Keepalive is reminder-based by design.
