#!/usr/bin/env bash
# PreToolUse (Edit|MultiEdit|Write) — what the assistant must not rewrite on its own:
#   1. Environment files.
#   2. The approval line of a feature spec, which only the person writes.
#   3. Existing tests: adding to them is the red phase; changing them asks.
#   4. Migrations already in git.
#   5. The hooks, their configuration and the project notes: changing them asks.
# Where each of them lives comes from the configuration (tests, specs,
# migrations_dirs, notes_dir).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT=$(cat)
TOOL=$(field "$INPUT" '.tool_name')
FILE=$(field "$INPUT" '.tool_input.file_path')
[[ -n "$FILE" ]] || finish

case "$FILE" in
  *..*) deny "Ruta con '..' rechazada: $FILE" ;;
esac

if is_secret_path "$FILE"; then
  deny "Los archivos de entorno no se editan desde el asistente: $(relative "$FILE"). Los cambia una persona$(ref secrets)."
fi

REL=$(relative "$FILE")
ABS=$(absolute "$FILE")

# The hooks and their configuration: changing them changes what is controlled.
case "$REL" in
  .claude/hooks/* | .claude/settings.json | .claude/settings.local.json | "$PROJECT_CONFIG_REL")
    ask "Vas a cambiar los hooks del asistente o su configuración ($REL), que deciden qué se controla. Apagar un control, como HARNESS_ALLOW_RED, lo decide una persona. Confirmá solo si te lo pidió."
    ;;
esac

# The project notes: they guide the commands and the reviewer, so changing them
# changes what is checked.
NOTES_DIR=$(cfg .notes_dir)
if [[ -n "$NOTES_DIR" && "$REL" == "${NOTES_DIR%/}/"* ]]; then
  ask "Vas a cambiar una nota del proyecto ($REL). Las notas guían a los comandos y al agente revisor, así que cambian lo que se revisa. Confirmá solo si te lo pidió una persona."
fi

# adds_lines($o; $n): $n keeps $o whole and only puts complete lines around it.
# Text added inside a line of $o, like "or True" after an assertion, is a change.
ADDS_LINES='def adds_lines($o; $n):
  ($n | split($o)) as $parts
  | if ($parts | length) < 2 then false
    else ($parts[0]) as $before | ($parts[1:] | join($o)) as $after
      | ($before == "" or ($before | endswith("\n")) or ($o | startswith("\n")))
        and ($after == "" or ($after | startswith("\n")) or ($o | endswith("\n")))
    end;'

# The text the edit removes and the text it leaves, joined across edits.
case "$TOOL" in
  MultiEdit)
    REMOVED=$(printf '%s' "$INPUT" | jq -r '[.tool_input.edits[]?.old_string] | join("\n")')
    ADDED=$(printf '%s' "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")')
    ONLY_ADDS=$(printf '%s' "$INPUT" | jq -r \
      "$ADDS_LINES"' [.tool_input.edits[]? | adds_lines(.old_string; .new_string)] | all')
    ;;
  Write)
    REMOVED=$([[ -f "$ABS" ]] && cat "$ABS")
    ADDED=$(field "$INPUT" '.tool_input.content')
    if [[ -f "$ABS" ]]; then
      ONLY_ADDS=$(printf '%s' "$INPUT" | jq -r --rawfile current "$ABS" \
        "$ADDS_LINES"' adds_lines($current | sub("\n+$"; ""); .tool_input.content)')
    else
      ONLY_ADDS=true
    fi
    ;;
  *)
    REMOVED=$(field "$INPUT" '.tool_input.old_string')
    ADDED=$(field "$INPUT" '.tool_input.new_string')
    ONLY_ADDS=$(printf '%s' "$INPUT" | jq -r \
      "$ADDS_LINES"' adds_lines(.tool_input.old_string; .tool_input.new_string)')
    ;;
esac

# 2. The approval line of a spec. The template keeps a placeholder, not an approval.
SPEC_GLOB=$(cfg .specs.glob)
SPEC_TEMPLATE=$(cfg .specs.template_dir)
MARKER=$(cfg .specs.approval_marker)
PENDING=$(cfg .specs.pending_value)

# approvals <text> → how many approval lines it has that are not the placeholder.
approvals() {
  local line rest count=0
  while IFS= read -r line; do
    [[ "$line" == *"$MARKER"* ]] || continue
    rest=${line#*"$MARKER"}
    rest="${rest#"${rest%%[![:space:]]*}"}"
    rest="${rest%"${rest##*[![:space:]]}"}"
    [[ "$rest" == "$PENDING" ]] || count=$((count + 1))
  done <<< "$1"
  echo "$count"
}
if [[ -n "$SPEC_GLOB" && -n "$MARKER" ]] \
  && ! [[ -n "$SPEC_TEMPLATE" && "$REL" == "${SPEC_TEMPLATE%/}/"* ]] \
  && [[ "$REL" == $SPEC_GLOB ]]; then
  if (( $(approvals "$ADDED") > $(approvals "$REMOVED") )); then
    deny "La línea «${MARKER//\*/}» de $REL la completa la persona que aprueba los casos, nunca un asistente$(ref approval). Dejala en «${PENDING}» y pedí la aprobación."
  fi
fi

# 3. Existing tests: inside a test directory, or named like a test file.
is_test=false
under "$REL" .tests.dirs && is_test=true
TEST_FILE_PATTERN=$(cfg .tests.file_pattern)
if [[ -n "$TEST_FILE_PATTERN" ]] && printf '%s' "$REL" | grep -qE -e "${TEST_FILE_PATTERN}\$"; then
  is_test=true
fi
# Lines that skip, expect to fail or single out a test: adding one disables others.
disablers() {
  printf '%s\n' "$1" | grep -cE \
    '(^|[^[:alnum:]_])(pytest\.)?mark\.(skip|skipif|xfail)|pytest\.(skip|xfail)\(|unittest\.skip|(^|[^[:alnum:]_])(it|test|describe)\.(skip|only|todo|fixme)|(^|[^[:alnum:]_])x(it|test|describe)\('
}
if $is_test && [[ -f "$ABS" ]]; then
  if (( $(disablers "$ADDED") > $(disablers "$REMOVED") )); then
    ask "Vas a deshabilitar un test de $REL (skip, xfail u only). Un test no se deshabilita sin la aprobación de una persona$(ref tests). Confirmá solo si la persona lo decidió."
  fi
  if [[ "$ONLY_ADDS" != "true" ]]; then
    ask "Vas a cambiar o borrar algo de un test existente ($REL). Nunca se modifica un test para que la suite pase: si el test está mal, frená y mostralo$(ref tests). Confirmá solo si la persona lo decidió."
  fi
fi

# 4. Migrations already in git.
if under "$REL" .migrations_dirs && [[ -f "$ABS" ]] \
  && git -C "$PROJECT_DIR" ls-files --error-unmatch "$REL" >/dev/null 2>&1; then
  ask "$REL es una migración ya versionada, y una migración aplicada no se edita: el cambio va en una migración nueva$(ref migrations). Confirmá solo si nunca se aplicó."
fi

finish
