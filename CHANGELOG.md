# Changelog

All notable changes to `claude-code-optimizer`. Version in `VERSION`.

## [1.0.1] - 2026-11-08

Patch for Copilot review on PR #1 (2 medium issues).

### Fixed
- Linux: gate rendered `PostToolUse` formatter hook on `auto_format` (was always emitted, pointing to missing `post-edit-format.sh` when `--auto-format` off). Matches Windows installer and opt-in docs.
- Windows: normalize `-OutputStyle` (and `-Profile`/`-Privacy`) to lowercase before writing settings. `ValidateSet` accepts mixed case, but `outputStyle` is case-sensitive — `Caveman-Ultra` now correctly writes `caveman-ultra`.
- Linux: normalize `--profile`/`--privacy`/`--output-style` to lowercase (accept `Caveman-Ultra`, store `caveman-ultra`).

## [1.0.0] - 2026-11-08

First versioned release. Branch: `release/v1.0.0`.

### Fixed
- Caveman source-of-truth: installers now copy `assets/output-styles/caveman.md` + `caveman-ultra.md` (synced from `caveman-output-style-claude-code` v1.2.0) instead of stale heredocs. Active style via `--output-style caveman|caveman-ultra|none` (default `caveman`) and lowercase `outputStyle` in settings.
- `--auto-format` documented as opt-in off (was incorrectly documented as on).
- `SessionStart` double-fire: reminder now `startup` only; `compact|resume` reserved for handoff resume.
- `handoff-precompact.sh` `$fallback_maxBytes` typo fixed; handoff model unpinned from `claude-sonnet-4-6` to `sonnet` alias (both platforms).
- `CLAUDE.local.md` no longer references non-existent `raw/` mirror; points to official docs URLs.

### Changed
- Cache TTL: tuned profile now sets canonical `promptCacheTtl: 1h` (v2.1.242+) in settings plus keeps legacy `ENABLE_PROMPT_CACHING_1H=1` env for older CLI. Merge preserves user keys and cleans stale `promptCacheTtl` on `official` profile.
- Tuned legacy/unverified flags (`SM_COMPACT`, `INTERLEAVED_THINKING`, `ADVISOR`, `GIT_INSTRUCTIONS`, `POLICY_SKILLS`, `MAX_MCP_OUTPUT_TOKENS`, `EXPERIMENTAL_AGENT_TEAMS`) explicitly marked legacy/unverified in code comments, README, and docs.
- README: removed unmeasured `%` claims (75%, 45%, 50-80%); output-style savings documented as voice-only, payload verbatim. `keep-coding-instructions` scope, case-sensitivity, cache invalidation on switch, and subagent non-inheritance documented.
- Keepalive documented as reminder-based; background `claude -p` pings documented as unreliable for main-conversation cache.
- Docs pinned with `Last verified: 2026-11-08` headers: `optimization-scripts`, `prompt-caching`, `session-memory`, `undocumented-features`. `experimentalSystemReminder` marked do-not-use.

### Added
- `VERSION` (1.0.0), `assets/output-styles/`, `--output-style` flag (both installers), `CHANGELOG.md`.
