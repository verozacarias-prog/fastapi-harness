#!/usr/bin/env bash
# Tests for the shape of the plugin: its manifests, the hook registry, the default
# configuration, the frontmatter of every command and agent, and that nothing in it
# belongs to one project or one person (proposal 0001).
#
# Usage: bash tests/test_plugin.sh
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASSED=0
FAILED=0

command -v jq >/dev/null 2>&1 || { echo "test_plugin: jq is required"; exit 1; }

expect() {
  local name=$1 want=$2 got=$3
  if [[ "$got" == "$want" ]]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "FAIL $name: expected $want, got $got"
  fi
}

valid_json() { [[ -f "$1" ]] && jq -e . "$1" >/dev/null 2>&1 && echo yes || echo no; }
json() { jq -r "$2 // empty" "$1" 2>/dev/null; }
# json_yes <file> <jq condition> → yes when the condition holds, no otherwise.
json_yes() { [[ "$(jq -r "$2" "$1" 2>/dev/null)" == true ]] && echo yes || echo no; }

# frontmatter_field <file> <field> → the value of a field of its frontmatter.
frontmatter_field() {
  awk -v f="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, f ": ") == 1 { print substr($0, length(f) + 3); exit }' "$1"
}
frontmatter_closed() {
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$1" \
    && echo yes || echo no
}

# ── Manifests ────────────────────────────────────────────────────────────────

PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"
expect "P-1 plugin.json is valid" yes "$(valid_json "$PLUGIN")"
expect "P-1 plugin name" fastapi-harness "$(json "$PLUGIN" .name)"
expect "P-1 plugin has a version" yes "$([[ -n "$(json "$PLUGIN" .version)" ]] && echo yes || echo no)"
expect "P-2 marketplace.json is valid" yes "$(valid_json "$MARKET")"
expect "P-2 marketplace name" fastapi-harness "$(json "$MARKET" .name)"
expect "P-2 marketplace has an owner" yes "$([[ -n "$(json "$MARKET" .owner.name)" ]] && echo yes || echo no)"
expect "P-2 the plugin entry matches the manifest" fastapi-harness "$(json "$MARKET" '.plugins[0].name')"
expect "P-2 the plugin lives at the root" ./ "$(json "$MARKET" '.plugins[0].source')"

# ── Hook registry ────────────────────────────────────────────────────────────

REGISTRY="$ROOT/hooks/hooks.json"
expect "P-3 hooks.json is valid" yes "$(valid_json "$REGISTRY")"
for hook in block-secret-reads.sh protect-tests-and-specs.sh block-dangerous-bash.sh verify-tests-on-stop.sh; do
  expect "P-3 $hook is registered" yes \
    "$(grep -qF "\${CLAUDE_PLUGIN_ROOT}/hooks/$hook" "$REGISTRY" 2>/dev/null && echo yes || echo no)"
  expect "P-3 $hook exists" yes "$([[ -f "$ROOT/hooks/$hook" ]] && echo yes || echo no)"
done
expect "P-3 Read matcher" yes "$(json_yes "$REGISTRY" '[.hooks.PreToolUse[]?.matcher] | index("Read") != null')"
expect "P-3 Bash matcher" yes "$(json_yes "$REGISTRY" '[.hooks.PreToolUse[]?.matcher] | index("Bash") != null')"
expect "P-3 Edit matcher" yes "$(json_yes "$REGISTRY" '[.hooks.PreToolUse[]?.matcher] | index("Edit|MultiEdit|Write") != null')"
expect "P-3 Stop hook" yes "$(json_yes "$REGISTRY" '(.hooks.Stop | length) > 0')"

# ── Default configuration ────────────────────────────────────────────────────

DEFAULTS="$ROOT/config/default.json"
expect "P-4 default.json is valid" yes "$(valid_json "$DEFAULTS")"
for key in integration_branch secrets_allowed tests specs migrations_dirs suites bash_rules rule_refs notes_dir; do
  expect "P-4 default.json declares $key" yes "$(json_yes "$DEFAULTS" "has(\"$key\")")"
done

# ── Commands and agent ───────────────────────────────────────────────────────

for name in ticket spec-drift security-audit ui-states; do
  file="$ROOT/commands/$name.md"
  expect "P-5 /$name exists" yes "$([[ -f "$file" ]] && echo yes || echo no)"
  [[ -f "$file" ]] || continue
  expect "P-5 /$name frontmatter is closed" yes "$(frontmatter_closed "$file")"
  expect "P-5 /$name has a description" yes "$([[ -n "$(frontmatter_field "$file" description)" ]] && echo yes || echo no)"
  expect "P-5 /$name reads the project notes" yes \
    "$(grep -q 'notes_dir' "$file" && echo yes || echo no)"
done

AGENT="$ROOT/agents/pr-reviewer.md"
expect "P-6 pr-reviewer exists" yes "$([[ -f "$AGENT" ]] && echo yes || echo no)"
if [[ -f "$AGENT" ]]; then
  expect "P-6 pr-reviewer frontmatter is closed" yes "$(frontmatter_closed "$AGENT")"
  expect "P-6 pr-reviewer name matches its file" pr-reviewer "$(frontmatter_field "$AGENT" name)"
  expect "P-6 pr-reviewer has a description" yes \
    "$([[ -n "$(frontmatter_field "$AGENT" description)" ]] && echo yes || echo no)"
  expect "P-6 pr-reviewer reads the project notes" yes "$(grep -q 'notes_dir' "$AGENT" && echo yes || echo no)"
fi

# ── Nothing of one project or one person ─────────────────────────────────────
# propuestas/ is the record and keeps where each piece came from.

LEAKS=$(grep -rIilE 'platita|ai4devs|zacarias|vzacarias|permitir_rojo|/Users/' "$ROOT" \
  --exclude-dir=.git --exclude-dir=propuestas --exclude=test_plugin.sh 2>/dev/null | sed "s|$ROOT/||")
expect "P-7 no project or personal names" "" "$LEAKS"

# ── The CLI validator, when it is installed ──────────────────────────────────

if command -v claude >/dev/null 2>&1; then
  expect "P-8 claude plugin validate" 0 "$(cd "$ROOT" && claude plugin validate . >/dev/null 2>&1; echo $?)"
fi

echo ""
echo "test_plugin: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
