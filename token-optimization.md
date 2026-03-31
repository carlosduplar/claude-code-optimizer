# Token Optimization Guide

## Quick Wins (Immediate 50%+ Reduction)

### 1. Pre-Process Documents Before Claude Sees Them

Convert binary documents to Markdown to eliminate base64 overhead:

```bash
# PDFs: Use pdftotext or markitdown
pdftotext -layout document.pdf document.txt
markitdown document.pdf > document.md

# Office documents
markitdown document.docx > document.md
markitdown spreadsheet.xlsx > spreadsheet.md
markitdown presentation.pptx > presentation.md

# Images: Pre-resize to max 2000x2000
magick input.jpg -resize 2000x2000\> -quality 85 output.jpg
```

**Why this works:**
- Images auto-resize to 2000x2000 max (see `imageResizer.ts`)
- PDFs >10 pages get reference treatment instead of inlining
- Base64 encoding increases size by ~33%

### 2. Use Pagination Religiously

Always use `offset` and `limit` when reading files >500 lines:

```
# Good
Read file.ts {"offset": 1, "limit": 100}

# Bad (expensive for large files)
Read file.ts
```

**Built-in limits:**
- Tool results >50K chars get persisted to disk
- Per-message aggregate: 200K chars max for parallel tools

### 3. Model Selection Strategy

**Cost Hierarchy (per million tokens):**
| Model | Input | Output | Use For |
|-------|-------|--------|---------|
| Haiku 3.5 | $0.80 | $4 | Quick tasks, token counting, simple queries |
| Sonnet 4.x | $3 | $15 | General development (default) |
| Opus 4.5 | $5 | $25 | Complex architecture |
| Opus 4.6 | $5 | $25 | Frontier capabilities |
| Opus 4.6 Fast | $30 | $150 | Priority routing only when needed |

**Tips:**
- Use Haiku for `/model haiku` when doing file searches or quick edits
- Switching models loses cached context—batch similar tasks by model
- Fast Mode costs 6x standard pricing

### 4. Context Management

**Enable Auto-Compact:**
```json
// ~/.claude.json or .claude.json in project
{
  "autoCompactEnabled": true
}
```

**Compact strategically:**
- Trigger manual `/compact` at ~150K tokens
- Never use `/clear` (destroys cached context)
- Compact before: large refactoring, multi-file operations, long sessions

**Set custom thresholds:**
```bash
# Trigger at 90% instead of default ~87%
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90

# Or set absolute window limit
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
```

---

## Advanced Optimizations

### 5. Avoid Parallel Tool Abuse

The system enforces a **200K character aggregate limit** per message for parallel tool results.

**Bad (expensive):**
```
# 10 parallel file reads, each 30K chars = 300K total
# System will persist 100K+ to disk
```

**Good:**
```
# Chain sequentially or use offset/limit
Read file1.ts {"limit": 50}
Read file2.ts {"limit": 50}
```

### 6. Use Grep Over Read for Searching

```
# Good
Grep pattern *.ts

# Bad
Read all files then search
```

### 7. Set Token Budgets in Prompts

Start messages with token budgets:
- `+500k` - shorthand for 500,000 tokens
- `+1m` - shorthand for 1,000,000 tokens
- `use 500k tokens` - verbose format

Example:
```
+500k Review this code and suggest improvements. Do not exceed 500k tokens.
```

### 8. Cache-Friendly Practices

Prompt cache hits require identical:
1. System prompt
2. Tools
3. Model
4. Messages prefix
5. **Thinking config** (changing this breaks cache!)

**Best practices:**
- Keep system prompt stable
- Don't change thinking settings mid-session
- Batch work by model

---

## Hook-Based Optimizations

### Auto-Resize Images Hook

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if command -v magick >/dev/null 2>&1 && [ -f \"$ARGUMENTS\" ] && [[ \"$ARGUMENTS\" =~ \\.(png|jpg|jpeg)$ ]]; then magick \"$ARGUMENTS\" -resize 2000x2000\\> -quality 85 /tmp/resized_$(basename \"$ARGUMENTS\"); fi",
        "if": "Read(*.{png,jpg,jpeg})"
      }]
    }]
  }
}
```

### Document Conversion Hook

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if command -v markitdown >/dev/null 2>&1 && [ -f \"$ARGUMENTS\" ] && [[ \"$ARGUMENTS\" =~ \\.(pdf|docx|xlsx)$ ]]; then markitdown \"$ARGUMENTS\" > \"${ARGUMENTS%.*}.md\" 2>/dev/null && echo \"Converted: ${ARGUMENTS%.*}.md\"; fi",
        "if": "Read(*.{pdf,docx,xlsx})"
      }]
    }]
  }
}
```

### Large File Warning Hook

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if [ -f \"$ARGUMENTS\" ] && [ $(stat -f%z \"$ARGUMENTS\" 2>/dev/null || stat -c%s \"$ARGUMENTS\" 2>/dev/null) -gt 50000 ]; then echo \"WARNING: Large file detected. Consider using offset/limit.\"; fi",
        "if": "Read(*.*)"
      }]
    }]
  }
}
```

---

## MCP Server Management

Each MCP server adds to system prompt size. Disable unused servers:

```bash
# List active MCP servers
/mcp list

# Disable unused servers
/mcp disable <server-name>
```

---

## Image/PDF Best Practices

### Images
- Resize before attaching (API limit: 5MB base64 ~3.75MB raw)
- Client auto-resizes to 2000x2000 max
- Use PNG for text, JPEG for photos
- Screenshots: PNG preserves text clarity

### PDFs
- Large PDFs (>3MB) get extracted to page images (expensive)
- PDFs >100 pages or >100MB are rejected
- Use `pages` parameter for partial reads:
  ```
  Read document.pdf {"pages": "1-10"}
  ```
- PDFs >10 pages get reference treatment (not inlined)

---

## Summary Checklist

| Action | Token Savings |
|--------|---------------|
| Pre-convert documents to Markdown | 50-80% |
| Pre-resize images to 2000x2000 | 60-80% |
| Use offset/limit for file reads | 70-90% |
| Use Grep over Read for searching | 80-95% |
| Chain vs parallel large tools | 40-60% |
| Use Haiku for simple tasks | 60-75% |
| Compact at 150K tokens | Prevents blocking |
| Batch by model (avoid switching) | Preserves cache |
| Set turn budgets (+500k) | Controlled spend |
| Disable unused MCP servers | Reduces prompt size |
