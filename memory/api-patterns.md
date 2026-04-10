# API Patterns

Frequently used APIs with verified examples.

## Template

### [API/Tool Name] - Confidence: HIGH/MEDIUM/LOW
**Use case**: When to use this
**Pattern**: Code example
**Gotchas**: Known issues or edge cases
**Docs**: Link to official docs

---

## Claude Code Internals

### PreToolUse Hook
**Use case**: Intercept and modify tool calls before execution
**Pattern**:
```json
{
  "event": "PreToolUse",
  "tool": "Read|Write|Edit|Bash",
  "command": "regex pattern for Bash",
  "file_path": "regex pattern for file tools"
}
```
**Gotchas**: Cannot override permissions, only block or modify
**Confidence**: HIGH
**Docs**: `raw/en/hooks.md`

### Environment Variables
**Use case**: Tune Claude Code behavior
**Pattern**: Export in shell profile or `.claude/.env`
```bash
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
export BASH_MAX_OUTPUT_LENGTH=10000
```
**Gotchas**: Some flags are internal-only, verify in docs first
**Confidence**: HIGH
**Docs**: `raw/en/settings.md`

## External Tools

### Context7
**Use case**: Verify library/framework documentation
**Pattern**: Use `context7-cli` MCP or `resolve-library-id` + `query-docs`
**Gotchas**: Must resolve library ID before querying
**Confidence**: HIGH
**Docs**: Use `raw/en/` local mirror as fallback
