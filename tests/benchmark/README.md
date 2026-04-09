# Claude Code Token Benchmark

Token measurement suite for Claude Code optimization validation.

## Quick Start

```bash
cd tests/benchmark/corpus
../run-all.sh
../report.sh
```

## Structure

```
tests/benchmark/
├── corpus/                 # Test project files
│   ├── data_processor.py   # CSV/data processing with bugs
│   ├── api_client.py       # HTTP client with bugs
│   ├── orm_models.py       # Database ORM with bugs
│   ├── auth_system.py      # Auth/JWT with bugs
│   ├── task_queue.py       # Queue/concurrency with bugs
│   ├── sample.pdf          # Binary test file
│   └── sample.png          # Image test file
├── results/                # Benchmark output
├── prompts.txt             # Fixed 5-prompt test sequence
├── parse-session.sh        # Transcript parser
├── parse-session.ps1       # Windows transcript parser
├── run-config.sh           # Single config runner
├── run-config.ps1          # Windows single config runner
├── run-all.sh              # Full A/B/C/D x3 runs
├── run-all.ps1             # Windows full benchmark
├── report.sh               # Results comparison
└── report.ps1              # Windows results report
```

## Configs

| Config | Description |
|--------|-------------|
| A | Baseline (no env vars, no CLAUDE.md) |
| B | Env vars only (DISABLE_AUTO_MEMORY, etc) |
| C | CLAUDE.md only (compact instructions) |
| D | Both optimizations |

## Prerequisites

- `claude -p` (headless mode) available
- `jq` installed for JSON parsing
- Bash or PowerShell 7

## Cost Formula

```
cost = input*0.000003 +
       cache_creation*0.00000375 +
       cache_read*0.0000003 +
       output*0.000015
```

## Metrics Captured

- `input_tokens` - Total input to API
- `output_tokens` - Total output from API
- `cache_read` - Cache hit tokens
- `cache_write` - Cache creation tokens
- `api_calls` - Number of API requests
- `compaction_events` - Memory compactions
- `estimated_cost_usd` - Calculated cost
- `duration_seconds` - Wall clock time

## Reproduction

For skeptics validating optimization claims:

```bash
git clone <repo>
cd tests/benchmark/corpus
../run-all.sh
../report.sh
```

Results print as table showing % change vs Config A baseline.

## Troubleshooting

**"claude -p not available"**
- Update Claude Code CLI to latest

**"jq required but not installed"**
- Termux: `pkg install jq`
- Ubuntu: `apt-get install jq`
- macOS: `brew install jq`

**No transcript found**
- Check `~/.claude/projects/` exists
- Verify claude created sessions
