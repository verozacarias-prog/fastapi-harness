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
expect "P-3 Read|Grep matcher" yes "$(json_yes "$REGISTRY" '[.hooks.PreToolUse[]?.matcher] | index("Read|Grep") != null')"
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

# ── Templates of a feature (proposal 0002) ───────────────────────────────────

TEMPLATES="$ROOT/templates/feature"
MARKER=$(json "$DEFAULTS" .specs.approval_marker)
PENDING=$(json "$DEFAULTS" .specs.pending_value)
SPEC_TEMPLATE="$TEMPLATES/spec.md"

expect "P-9 spec.md template exists" yes "$([[ -f "$SPEC_TEMPLATE" ]] && echo yes || echo no)"
expect "P-9 one pending approval line per cut" 3 \
  "$(grep -cF -- "$MARKER $PENDING" "$SPEC_TEMPLATE" 2>/dev/null || true)"

# P-10 and P-11: the template, copied into a throwaway project, works with the hook
# and its default configuration.
PROJECT=$(mktemp -d)
trap 'rm -rf "$PROJECT"' EXIT
APPROVED="$MARKER Ana, 2026-11-23"
approve_json() {
  jq -n --arg p "$1" --arg o "$MARKER $PENDING" --arg n "$APPROVED" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}'
}
hook_decision() {
  local out d
  out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$ROOT/hooks/protect-tests-and-specs.sh" 2>/dev/null)
  d=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // .decision // empty' 2>/dev/null)
  echo "${d:-allow}"
}
TEMPLATE_DIR=$(json "$DEFAULTS" .specs.template_dir)
mkdir -p "$PROJECT/${TEMPLATE_DIR%/}" "$PROJECT/docs/features/FEAT-1"
if [[ -f "$SPEC_TEMPLATE" ]]; then
  cp "$SPEC_TEMPLATE" "$PROJECT/${TEMPLATE_DIR%/}/spec.md"
  cp "$SPEC_TEMPLATE" "$PROJECT/docs/features/FEAT-1/spec.md"
  git -C "$PROJECT" init -q
  git -C "$PROJECT" -c user.name=test -c user.email=test@example.invalid add -A
  git -C "$PROJECT" -c user.name=test -c user.email=test@example.invalid commit -q -m init
  expect "P-10 approve in the project template" allow \
    "$(hook_decision "$(approve_json "$PROJECT/${TEMPLATE_DIR%/}/spec.md")")"
  expect "P-11 approve in a feature spec" deny \
    "$(hook_decision "$(approve_json "$PROJECT/docs/features/FEAT-1/spec.md")")"
else
  expect "P-10 approve in the project template" allow "missing template"
  expect "P-11 approve in a feature spec" deny "missing template"
fi

expect "P-12 pr.md template exists" yes "$([[ -f "$TEMPLATES/pr.md" ]] && echo yes || echo no)"
expect "P-12 ui_contract.md template exists" yes "$([[ -f "$TEMPLATES/ui_contract.md" ]] && echo yes || echo no)"
for state in 'Cargando' 'Con contenido' 'Vacío' 'Error'; do
  expect "P-12 ui_contract.md has the state $state" yes \
    "$(grep -qF "| $state |" "$TEMPLATES/ui_contract.md" 2>/dev/null && echo yes || echo no)"
done

# ── What the project has to have written (proposal 0002) ─────────────────────

expect "P-13 README section" yes \
  "$(grep -qE '^#+ Lo que el proyecto tiene que tener escrito' "$ROOT/README.md" && echo yes || echo no)"
expect "P-13 no copy of the method" "" \
  "$(cd "$ROOT" && ls metodo.md templates/agents-section.md 2>/dev/null)"

# ── Secrets (proposal 0002) ──────────────────────────────────────────────────

DENY="$ROOT/templates/settings-deny.json"
expect "P-14 settings-deny.json is valid" yes "$(valid_json "$DENY")"
for name in '.env' 'credentials*' 'id_rsa' 'id_ed25519' '*.pem' '*.key' 'service-account*.json'; do
  expect "P-14 deny covers $name" yes \
    "$(json_yes "$DENY" "[.permissions.deny[]?] | index(\"Read(**/$name)\") != null")"
done

TICKET="$ROOT/commands/ticket.md"
expect "P-15 /ticket names specs.template_dir" yes \
  "$(grep -qF 'specs.template_dir' "$TICKET" && echo yes || echo no)"
expect "P-15 /ticket offers the plugin template" yes \
  "$(grep -qF '${CLAUDE_PLUGIN_ROOT}/templates/feature' "$TICKET" && echo yes || echo no)"

# ── Nothing of one project or one person ─────────────────────────────────────
# proposals/ is the record and keeps where each piece came from. The author is
# named only where authorship is declared: LICENSE and the author of plugin.json.

LEAKS_PATTERN='platita|ai4devs|zacar[ií]as|vzacarias|permitir_rojo|/Users/'
LEAKS=$(grep -rIilE "$LEAKS_PATTERN" "$ROOT" \
  --exclude-dir=.git --exclude-dir=proposals --exclude=test_plugin.sh \
  --exclude=LICENSE --exclude=plugin.json 2>/dev/null | sed "s|$ROOT/||")
expect "P-7 no project or personal names" "" "$LEAKS"
expect "P-7 templates/ is there to be checked" yes "$([[ -d "$ROOT/templates" ]] && echo yes || echo no)"
expect "P-7 plugin.json names a person only as its author" no \
  "$(jq 'del(.author)' "$PLUGIN" 2>/dev/null | grep -qiE "$LEAKS_PATTERN" && echo yes || echo no)"

# ── The CLI validator, when it is installed ──────────────────────────────────

if command -v claude >/dev/null 2>&1; then
  expect "P-8 claude plugin validate" 0 "$(cd "$ROOT" && claude plugin validate . >/dev/null 2>&1; echo $?)"
fi

echo ""
echo "test_plugin: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
