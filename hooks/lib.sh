#!/usr/bin/env bash
# Common helpers for the hooks of the plugin.
#
# Every hook sources this file. A hook must never break the session: when
# something it needs is missing (jq, git, a test runner), it lets the action
# through instead of failing on every turn.
#
# What belongs to one project comes from its .claude/fastapi-harness.json, merged
# over config/default.json. Without that file the defaults apply; with a broken
# one too, and the person is told.
#
# Adapted from the SDD Harness Kit (github.com/DisTinta/sdd-harness-kit, MIT).

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Without jq the hooks cannot read their input: they turn themselves off.
command -v jq >/dev/null 2>&1 || exit 0

# ── Configuration ────────────────────────────────────────────────────────────

DEFAULTS_FILE="$PLUGIN_ROOT/config/default.json"
PROJECT_CONFIG_REL=".claude/fastapi-harness.json"
PROJECT_CONFIG="$PROJECT_DIR/$PROJECT_CONFIG_REL"
CONFIG_WARNING=""

CONFIG=$(jq -c . "$DEFAULTS_FILE" 2>/dev/null) || CONFIG='{}'
if [[ -f "$PROJECT_CONFIG" ]]; then
  if MERGED=$(jq -cs '.[0] * .[1]' "$DEFAULTS_FILE" "$PROJECT_CONFIG" 2>/dev/null); then
    CONFIG=$MERGED
  else
    CONFIG_WARNING="$PROJECT_CONFIG_REL no es un JSON válido: los hooks usan los valores por defecto del plugin hasta que se corrija."
  fi
fi

# cfg <jq path> → a value of the configuration, or an empty string.
cfg() {
  printf '%s' "$CONFIG" | jq -r "$1 // empty" 2>/dev/null
}

# cfg_list <jq path> → the items of a list of the configuration, one per line.
cfg_list() {
  printf '%s' "$CONFIG" | jq -r "($1 // [])[]" 2>/dev/null
}

# ref <rule> → " (where the project writes that rule)", or nothing.
ref() {
  local where
  where=$(cfg ".rule_refs[\"$1\"]")
  [[ -n "$where" ]] && printf ' (%s)' "$where"
  return 0
}

# ── Input ────────────────────────────────────────────────────────────────────

# field <json> <jq path> → the value, or an empty string.
field() {
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

# relative <path> → the path relative to the project root.
relative() {
  local path=$1
  case "$path" in
    "$PROJECT_DIR"/*) path=${path#"$PROJECT_DIR"/} ;;
  esac
  printf '%s' "$path"
}

# absolute <path> → the path anchored at the project root.
absolute() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$PROJECT_DIR" "$1" ;;
  esac
}

# under <relative path> <jq path of a list of dirs> → success when it is inside one.
under() {
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" && "$1" == "${dir%/}/"* ]] && return 0
  done < <(cfg_list "$2")
  return 1
}

# ── PreToolUse decisions ─────────────────────────────────────────────────────

_decide() {
  jq -n --arg decision "$1" --arg reason "$2" --arg warning "$CONFIG_WARNING" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: $reason
    }
  } + (if $warning == "" then {} else {systemMessage: $warning} end)'
  exit 0
}

deny() { _decide deny "$1"; }
ask() { _decide ask "$1"; }

# finish → let the action through, telling the person if the configuration is broken.
finish() {
  [[ -n "$CONFIG_WARNING" ]] && jq -n --arg message "$CONFIG_WARNING" '{systemMessage: $message}'
  exit 0
}

# ── Stop decision ────────────────────────────────────────────────────────────

block() {
  jq -n --arg reason "$1" --arg warning "$CONFIG_WARNING" \
    '{decision: "block", reason: $reason} + (if $warning == "" then {} else {systemMessage: $warning} end)'
  exit 0
}

# warn <message> → let the turn close, and show the message to the person.
warn() {
  local message=$1
  [[ -n "$CONFIG_WARNING" ]] && message="$CONFIG_WARNING $message"
  jq -n --arg message "$message" '{systemMessage: $message}'
  exit 0
}

# ── Rules shared by more than one hook ───────────────────────────────────────

# is_secret_path <path> → success when the file holds secrets or credentials.
# An entry of secrets_allowed with a slash is one exact path of the project; one
# without a slash is a file name allowed anywhere, like the .env.example template.
is_secret_path() {
  local name rel allowed
  rel=$(relative "$1")
  name=${1##*/}
  while IFS= read -r allowed; do
    [[ -n "$allowed" ]] || continue
    if [[ "$allowed" == */* ]]; then
      [[ "$rel" == "$allowed" ]] && return 1
    else
      [[ "$name" == "$allowed" ]] && return 1
    fi
  done < <(cfg_list .secrets_allowed)
  case "$name" in
    .env | .env.* | *.env) return 0 ;;
    credentials* | id_rsa | id_ed25519 | *.pem | *.key | service-account*.json) return 0 ;;
  esac
  return 1
}
