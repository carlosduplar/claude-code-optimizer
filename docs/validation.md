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

- Linux: `--expect-unsafe` (assert unsafe high-risk patterns are present)
- Windows: `-ExpectUnsafe` (assert unsafe high-risk patterns are present)

Use these only when optimizer was run with unsafe broad auto-approve enabled.

## Runtime hook test (actual trigger verification)

Static validation checks configuration shape only. To verify hooks are actually firing at runtime, run:

### Linux / macOS / WSL

```bash
./scripts/linux/test-hooks-runtime.sh
```

### Windows

```powershell
.\scripts\windows\test-hooks-runtime.ps1
```

Runtime test validates:

- `SessionStart`, `PreToolUse` hook events are emitted
- `Read` hook does not mutate the original test file
- file-guard blocks traversal-style command attempts

Prerequisites: `claude` CLI authenticated, runtime hooks installed in `~/.claude/settings.json`, and `tests/test-image.png` present.

## What is validated

- schema presence
- env object presence
- PreToolUse and SessionStart hooks configured (PostToolUse removed - no benefit)
- permissions deny list configured
- profile-specific tuning keys
- privacy-specific keys
- default allowlist presence
- unsafe high-risk pattern presence/absence

## Keepalive behavior

Validation does not assert fake `cache_keepalive` hook output. Keepalive is reminder-based by design.
