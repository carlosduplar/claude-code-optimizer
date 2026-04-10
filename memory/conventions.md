# Code Conventions

Language-agnostic project conventions. Validated patterns only.

## Template

### [Convention Name]
**Applies to**: File patterns (e.g., `*.py`, `src/**/*.ts`)
**Rule**: Specific convention
**Rationale**: Why this convention
**Confidence**: HIGH/MEDIUM/LOW

---

## General Conventions

### Error Handling
**Applies to**: All scripts
**Rule**: Fail-closed - on error, block by default (`trap ERR`)
**Rationale**: Prevents unsafe execution when validation logic fails
**Confidence**: HIGH

### Output Format
**Applies to**: All shell output
**Rule**: One concept per line, fragments OK, no filler
**Rationale**: Matches CLAUDE.md communication style
**Confidence**: HIGH

## Language-Specific

### Bash
**Applies to**: `*.sh`, `scripts/linux/*`
**Rule**: Use `#!/bin/bash` with `set -euo pipefail`
**Rationale**: Strict mode prevents silent failures
**Confidence**: HIGH

### PowerShell
**Applies to**: `*.ps1`, `scripts/windows/*`
**Rule**: Use `$ErrorActionPreference = 'Stop'`
**Rationale**: Consistent error handling across platforms
**Confidence**: HIGH
