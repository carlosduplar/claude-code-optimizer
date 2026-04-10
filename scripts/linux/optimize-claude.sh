#!/usr/bin/env bash
# Claude Code optimizer (official baseline + tuned overlay)

set -euo pipefail

PROFILE="tuned"
PRIVACY="max"
UNSAFE_AUTO_APPROVE=false
AUTO_FORMAT=false
DRY_RUN=false
SKIP_DEPS=false
VERIFY_ONLY=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOKS_DIR="${CLAUDE_DIR}/hooks"

info() { echo "[INFO] $1"; }
success() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1" >&2; }

usage() {
  cat <<'EOF'
Usage: optimize-claude.sh [options]

Options:
  --profile official|tuned   Config profile (default: tuned)
  --privacy standard|max     Privacy level (default: max)
  --unsafe-auto-approve      Enable broad Bash auto-approve allowlist
  --auto-format              Enable post-edit formatter hook
  --dry-run                  Print actions without writing files
  --skip-deps                Skip dependency checks
  --verify                   Verify current ~/.claude/settings.json only
  --help                     Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        PROFILE="$2"; shift 2 ;;
      --privacy)
        PRIVACY="$2"; shift 2 ;;
      --unsafe-auto-approve)
        UNSAFE_AUTO_APPROVE=true; shift ;;
      --auto-format)
        AUTO_FORMAT=true; shift ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      --skip-deps)
        SKIP_DEPS=true; shift ;;
      --verify)
        VERIFY_ONLY=true; shift ;;
      --help|-h)
        usage; exit 0 ;;
      *)
        err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  [[ "$PROFILE" =~ ^(official|tuned)$ ]] || { err "--profile must be official|tuned"; exit 1; }
  [[ "$PRIVACY" =~ ^(standard|max)$ ]] || { err "--privacy must be standard|max"; exit 1; }
}

check_deps() {
  $SKIP_DEPS && return 0
  local missing=()
  for cmd in python3 jq; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required dependencies: ${missing[*]}"
    err "Install them and re-run, or use --skip-deps if you know what you are doing."
    exit 1
  fi
}

write_hook_scripts() {
  $DRY_RUN && { info "[dry-run] would write hooks under ${HOOKS_DIR}"; return 0; }

  mkdir -p "$HOOKS_DIR"
  rm -f "${HOOKS_DIR}/posttooluse.sh"
  if ! $AUTO_FORMAT; then
    rm -f "${HOOKS_DIR}/post-edit-format.sh"
  fi

  # Copy hooks from script directory
  local SCRIPT_HOOKS_DIR="${SCRIPT_DIR}/hooks"
  if [[ -d "$SCRIPT_HOOKS_DIR" ]]; then
    cp "$SCRIPT_HOOKS_DIR"/*.sh "$HOOKS_DIR/" 2>/dev/null || true
  fi

  cat > "${HOOKS_DIR}/pretooluse.sh" <<'HOOKEOF'
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"

if [[ "$tool_name" != "Read" || -z "$file_path" || ! -f "$file_path" ]]; then
  exit 0
fi

ext="${file_path##*.}"
ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
base="/tmp/claude-read-$(date +%s)-$$"

emit_redirect() {
  local target="$1"
  local note="$2"
  jq -n --arg p "$target" --arg n "$note" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: { file_path: $p },
      additionalContext: $n
    }
  }'
}

case "$ext" in
  png|jpg|jpeg|webp|gif|bmp|tif|tiff)
    if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
      out="${base}.${ext}"
      if command -v magick >/dev/null 2>&1; then
        magick "$file_path" -resize "2000x2000>" -quality "85" "$out" >/dev/null 2>&1 || exit 0
      else
        convert "$file_path" -resize "2000x2000>" -quality "85" "$out" >/dev/null 2>&1 || exit 0
      fi
      [[ -f "$out" ]] && emit_redirect "$out" "Read hook used non-mutating optimized image copy." && exit 0
    fi
    ;;
  pdf)
    if command -v pdftotext >/dev/null 2>&1; then
      out="${base}.txt"
      pdftotext -layout "$file_path" "$out" >/dev/null 2>&1 || exit 0
      [[ -s "$out" ]] && emit_redirect "$out" "Read hook used non-mutating extracted PDF text copy." && exit 0
    fi
    ;;
  doc|docx|xls|xlsx|ppt|pptx)
    if command -v markitdown >/dev/null 2>&1; then
      out="${base}.md"
      markitdown "$file_path" > "$out" 2>/dev/null || exit 0
      [[ -s "$out" ]] && emit_redirect "$out" "Read hook used non-mutating markitdown extraction copy." && exit 0
    fi
    ;;
esac

exit 0
HOOKEOF

  cat > "${HOOKS_DIR}/file-guard.sh" <<'HOOKEOF'
#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"
command_str="$(echo "$input" | jq -r '.tool_input.command // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
project_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
[[ -z "$project_dir" ]] && project_dir="$PWD"
project_dir="$(realpath -m "$project_dir")"

patterns=(
  '\.env$'
  '\.env\.'
  '\.git/'
  '\.ssh/'
  'id_rsa'
  'id_ed25519'
  '\.pem$'
  '\.key$'
  'credentials\.json$'
  'secrets\.'
)

block() {
  local why="$1"
  echo "BLOCKED: ${why}" >&2
  exit 2
}

is_outside_project() {
  local raw_path="$1"
  local resolved
  [[ -z "$raw_path" ]] && return 1
  raw_path="${raw_path/#\~/$HOME}"
  resolved="$(realpath -m "$raw_path")"
  [[ "$resolved" != "$project_dir" && "$resolved" != "$project_dir/"* ]]
}

match_any() {
  local value="$1"
  for p in "${patterns[@]}"; do
    if echo "$value" | grep -qE "$p"; then
      return 0
    fi
  done
  return 1
}

if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  if [[ -n "$file_path" ]] && match_any "$file_path"; then
    block "path '$file_path' matches protected pattern"
  fi
  if [[ -n "$file_path" ]] && is_outside_project "$file_path"; then
    block "write/edit outside workspace is blocked: '$file_path'"
  fi
fi

if [[ "$tool_name" == "Bash" && -n "$command_str" ]]; then
  if match_any "$command_str"; then
    block "bash command references protected path/pattern"
  fi
  if echo "$command_str" | grep -qiE '^[[:space:]]*(cat|head|tail|grep|rg|find)\b'; then
    if echo "$command_str" | grep -qE '(^|[[:space:]])\.\./'; then
      block "path traversal is blocked for high-risk read commands"
    fi
    while IFS= read -r token; do
      [[ -z "$token" ]] && continue
      if is_outside_project "$token"; then
        block "high-risk read command target outside workspace: '$token'"
      fi
    done < <(echo "$command_str" | grep -oE '(~?/[^[:space:];|&]+|\.{1,2}/[^[:space:];|&]+)' || true)
  fi
fi

exit 0
HOOKEOF

  cat > "${HOOKS_DIR}/posttoolusefailure.sh" <<'HOOKEOF'
#!/usr/bin/env bash
# PostToolUseFailure: Log errors with 1MB rotation
set -euo pipefail

LOG_DIR="${HOME}/.claude/logs/errors"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/${DATE}.log"

# Rotate if > 1MB
if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 1048576 ]]; then
  mv "$LOG_FILE" "${LOG_DIR}/${DATE}-1.log"
fi

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
error="$(echo "$input" | jq -r '.error // empty')"

TIMESTAMP=$(date -Iseconds)
echo "[${TIMESTAMP}] [${tool_name}] ${error}" >> "$LOG_FILE"

exit 0
HOOKEOF

  cat > "${HOOKS_DIR}/session-start-reminder.sh" <<'HOOKEOF'
#!/usr/bin/env bash
# Reminder only; no guaranteed keepalive automation.
echo "Keepalive reminder: if you expect >5m idle periods, run /loop manually."
exit 0
HOOKEOF

  cat > "${HOOKS_DIR}/notify.sh" <<'HOOKEOF'
#!/usr/bin/env bash
# Notification hook - minimal, just acknowledges
exit 0
HOOKEOF

  if $AUTO_FORMAT; then
    cat > "${HOOKS_DIR}/post-edit-format.sh" <<'HOOKEOF'
#!/usr/bin/env bash
set -euo pipefail
input="$(cat)"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0
ext="${file_path##*.}"
ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
case "$ext" in
  js|jsx|ts|tsx|json|css|scss|less|html|htm|md|markdown|yaml|yml)
    command -v prettier >/dev/null 2>&1 && prettier --write "$file_path" >/dev/null 2>&1 || true ;;
  py)
    if command -v black >/dev/null 2>&1; then black --quiet "$file_path" >/dev/null 2>&1 || true
    elif command -v autopep8 >/dev/null 2>&1; then autopep8 --in-place "$file_path" >/dev/null 2>&1 || true
    fi ;;
esac
exit 0
HOOKEOF
  fi

  chmod +x "$HOOKS_DIR"/*.sh
  success "Hook scripts updated"
}

render_settings_json() {
  python3 - <<'PY'
import json, os

profile = os.environ["OPT_PROFILE"]
privacy = os.environ["OPT_PRIVACY"]
unsafe = os.environ["OPT_UNSAFE"] == "1"
auto_format = os.environ["OPT_AUTO_FORMAT"] == "1"
hooks_dir = os.environ["OPT_HOOKS_DIR"]

default_allow = [
  "Bash(ls *)", "Bash(ll *)", "Bash(dir *)",
  "Bash(Get-ChildItem *)", "Bash(gci *)",
  "Bash(pwd)", "Bash(Get-Location)", "Bash(gl)",
  "Bash(which *)", "Bash(where *)", "Bash(Get-Command *)", "Bash(gcm *)",
  "Bash(git status*)", "Bash(git log*)", "Bash(git diff*)", "Bash(git branch*)", "Bash(git stash list*)", "Bash(git remote*)", "Bash(git config*)",
  "Bash(npm list*)", "Bash(pip list*)", "Bash(pip show*)", "Bash(pip freeze*)", "Bash(Get-Package*)",
  "Bash(*--version)", "Bash(* -v)", "Bash(*--help*)",
]

unsafe_allow = [
  "Bash(find *)", "Bash(grep *)", "Bash(rg *)",
  "Bash(cat *)", "Bash(head *)", "Bash(tail *)", "Bash(wc *)", "Bash(sort *)",
  "Bash(uniq *)", "Bash(git show*)", "Bash(npm run*)",
]

settings = {
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {"commit": "", "pr": ""},
  "env": {},
  "permissions": {
    "allow": list(default_allow),
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Edit(./.env)",
      "Edit(./.env.*)",
      "Edit(./secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/pretooluse.sh", "timeout": 30}
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit|Bash",
        "hooks": [
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/file-guard.sh", "timeout": 10},
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/bash-guard.sh", "timeout": 5},
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/write-guard.sh", "timeout": 5}
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/posttoolusefailure.sh", "timeout": 5}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/session-start-reminder.sh", "timeout": 5}
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/notify.sh", "timeout": 15}
        ]
      }
    ]
  },
}

if auto_format:
  settings["hooks"]["PostToolUse"] = [
    {
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [
        {"type": "command", "shell": "bash", "command": f"bash {hooks_dir}/post-edit-format.sh", "timeout": 30}
      ]
    }
  ]

# official baseline
settings["env"]["DISABLE_TELEMETRY"] = "1"
if privacy == "max":
  settings["env"]["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

# tuned overlay
if profile == "tuned":
  settings["env"].update(
    {
      "BASH_MAX_OUTPUT_LENGTH": "10000",
      "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "180000",
      "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80",
      "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
      "ENABLE_CLAUDE_CODE_SM_COMPACT": "true",
      "DISABLE_INTERLEAVED_THINKING": "true",
      "CLAUDE_CODE_DISABLE_ADVISOR_TOOL": "true",
      "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "true",
      "CLAUDE_CODE_DISABLE_POLICY_SKILLS": "true",
      "OTEL_LOG_USER_PROMPTS": "0",
      "OTEL_LOG_TOOL_DETAILS": "0",
      "MAX_MCP_OUTPUT_TOKENS": "25000",
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    }
  )

if unsafe:
  settings.setdefault("permissions", {}).setdefault("allow", []).extend(unsafe_allow)
  settings["permissions"]["allow"] = list(dict.fromkeys(settings["permissions"]["allow"]))

print(json.dumps(settings))
PY
}

merge_settings() {
  local rendered="$1"
  $DRY_RUN && { echo "$rendered" | python3 -m json.tool; return 0; }

  mkdir -p "$CLAUDE_DIR"

  if [[ -f "$SETTINGS_FILE" ]]; then
    python3 - <<PY
import json
from pathlib import Path

p = Path(r"${SETTINGS_FILE}")
existing = json.loads(p.read_text(encoding="utf-8"))
incoming = json.loads(r'''${rendered}''')
managed_env_keys = {
    "DISABLE_TELEMETRY",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
    "BASH_MAX_OUTPUT_LENGTH",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY",
    "ENABLE_CLAUDE_CODE_SM_COMPACT",
    "DISABLE_INTERLEAVED_THINKING",
    "CLAUDE_CODE_DISABLE_ADVISOR_TOOL",
    "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS",
    "CLAUDE_CODE_DISABLE_POLICY_SKILLS",
    "OTEL_LOG_USER_PROMPTS",
    "OTEL_LOG_TOOL_DETAILS",
    "MAX_MCP_OUTPUT_TOKENS",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
}
legacy_managed_allow = {
    "Bash(find . -*)",
    "Bash(echo *)", "Bash(printenv *)", "Bash(env | *)",
    "Bash(ps *)", "Bash(top -n *)", "Bash(htop -n *)",
    "Bash(curl -I *)", "Bash(curl --head *)", "Bash(ping -c *)", "Bash(nslookup *)", "Bash(dig *)",
    "Bash(mkdir *)", "Bash(rmdir *)", "Bash(touch *)", "Bash(mv *)", "Bash(cp *)",
    "Bash(make *)", "Bash(cmake *)", "Bash(npm run *)", "Bash(yarn *)", "Bash(pnpm *)",
    "Bash(tsc *)", "Bash(eslint *)", "Bash(prettier *)", "Bash(ruff *)", "Bash(black *)",
    "Bash(docker ps *)", "Bash(docker images *)", "Bash(docker-compose ps *)",
}
unsafe_managed_allow = {
    "Bash(find *)", "Bash(grep *)", "Bash(rg *)",
    "Bash(cat *)", "Bash(head *)", "Bash(tail *)", "Bash(wc *)", "Bash(sort *)",
    "Bash(uniq *)", "Bash(git show*)", "Bash(npm run*)",
}
managed_deny = {
    "Read(./.env)",
    "Read(./.env.*)",
    "Read(./secrets/**)",
    "Edit(./.env)",
    "Edit(./.env.*)",
    "Edit(./secrets/**)",
}
managed_hook_keys = {"PreToolUse", "SessionStart", "PostToolUse", "PostToolUseFailure", "Notification"}

def unique(values):
    seen = set()
    out = []
    for value in values:
        if isinstance(value, str) and value and value not in seen:
            seen.add(value)
            out.append(value)
    return out

merged = dict(existing)

existing_env = existing.get("env", {}) if isinstance(existing.get("env"), dict) else {}
preserved_env = {k: v for k, v in existing_env.items() if k not in managed_env_keys}
merged["env"] = {**preserved_env, **incoming.get("env", {})}

existing_permissions = existing.get("permissions", {}) if isinstance(existing.get("permissions"), dict) else {}
incoming_permissions = incoming.get("permissions", {}) if isinstance(incoming.get("permissions"), dict) else {}
managed_allow = set(incoming_permissions.get("allow", [])) | unsafe_managed_allow | legacy_managed_allow
preserved_allow = [
    entry
    for entry in existing_permissions.get("allow", [])
    if isinstance(entry, str) and entry not in managed_allow
]
preserved_deny = [
    entry
    for entry in existing_permissions.get("deny", [])
    if isinstance(entry, str) and entry not in managed_deny
]
merged_permissions = {
    k: v for k, v in existing_permissions.items() if k not in {"allow", "deny"}
}
merged_permissions["allow"] = unique(preserved_allow + incoming_permissions.get("allow", []))
merged_permissions["deny"] = unique(preserved_deny + incoming_permissions.get("deny", []))
merged["permissions"] = merged_permissions

existing_hooks = existing.get("hooks", {}) if isinstance(existing.get("hooks"), dict) else {}
incoming_hooks = incoming.get("hooks", {}) if isinstance(incoming.get("hooks"), dict) else {}
preserved_hooks = {
    k: v for k, v in existing_hooks.items() if k not in managed_hook_keys
}
merged["hooks"] = {**preserved_hooks, **incoming_hooks}

for key, value in incoming.items():
    if key not in {"env", "permissions", "hooks"}:
        merged[key] = value

p.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
print("merged")
PY
  else
    echo "$rendered" | python3 -m json.tool > "$SETTINGS_FILE"
  fi

  success "Updated ${SETTINGS_FILE}"
}

verify_settings() {
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    err "Missing ${SETTINGS_FILE}"
    exit 1
  fi

  python3 - <<PY
import json
from pathlib import Path
p = Path(r"${SETTINGS_FILE}")
d = json.loads(p.read_text(encoding="utf-8"))
checks = [
  ("schema", "\$schema" in d),
  ("env", isinstance(d.get("env"), dict)),
  ("hooks.PreToolUse", isinstance(d.get("hooks", {}).get("PreToolUse"), list)),
  ("hooks.SessionStart", isinstance(d.get("hooks", {}).get("SessionStart"), list)),
  ("permissions.deny", isinstance(d.get("permissions", {}).get("deny"), list)),
]
failed = [k for k, ok in checks if not ok]
for k, ok in checks:
  print(f"[{'PASS' if ok else 'FAIL'}] {k}")
if failed:
  raise SystemExit(1)
PY
}

main() {
  parse_args "$@"

  if $VERIFY_ONLY; then
    verify_settings
    exit 0
  fi

  check_deps
  write_hook_scripts

  export OPT_PROFILE="$PROFILE"
  export OPT_PRIVACY="$PRIVACY"
  export OPT_UNSAFE="$($UNSAFE_AUTO_APPROVE && echo 1 || echo 0)"
  export OPT_AUTO_FORMAT="$($AUTO_FORMAT && echo 1 || echo 0)"
  export OPT_HOOKS_DIR="$HOOKS_DIR"

  settings_json="$(render_settings_json)"
  merge_settings "$settings_json"

  $UNSAFE_AUTO_APPROVE && warn "Unsafe auto-approve is enabled. This broad allowlist is high-risk."
  if ! $DRY_RUN; then
    verify_settings
  fi

  success "Done. Profile=${PROFILE}, privacy=${PRIVACY}, settings=${SETTINGS_FILE}"
}

main "$@"
