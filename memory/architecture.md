# Architecture Decisions

Record validated architectural decisions here. Only confirmed patterns, not experiments.

## Template

### [Decision Name] - YYYY-MM-DD
**Context**: What problem were we solving?
**Decision**: What did we decide?
**Rationale**: Why this approach?
**Confidence**: HIGH/MEDIUM/LOW
**Validation**: How was this confirmed?

---

## Decisions

### Session Memory Architecture - 2025-04-10
**Context**: Need cross-session retention of validated patterns without cache invalidation
**Decision**: Use `memory/` directory with MEMORY.md as index (max 200 lines), satellite files for details
**Rationale**: File-based persistence survives session restarts, git-trackable, human-readable
**Confidence**: HIGH
**Validation**: Pattern from Claude Code OS article, adapted for optimizer project
