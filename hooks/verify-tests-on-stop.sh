#!/usr/bin/env bash
# Stop — the turn does not close with a test suite of the project in the red.
#
# The suites come from the configuration (suites). Each one runs only when the
# paths it watches have uncommitted changes, new files included. A suite whose
# only changes are tests is in the red phase of test-first work and is let
# through. Integration tests, e2e, lint and types stay in pre-commit and in CI.
#
# It blocks once. On the second attempt (stop_hook_active) it runs the suites
# again and, if one is still red, lets the turn close but tells the person:
# blocking again could leave the assistant in a loop on a test it cannot fix.
# When a suite cannot run because its runner is missing, the turn closes with a
# warning too.
#
# Escape for a local exploration, never inside a delivery: HARNESS_ALLOW_RED=1
# in the "env" of .claude/settings.local.json.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT=$(cat)
SECOND_ATTEMPT=$(field "$INPUT" '.stop_hook_active')
[[ "${HARNESS_ALLOW_RED:-}" == "1" ]] && finish
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || finish

# changed <path>... → the uncommitted files under those paths, one per line.
changed() {
  git -C "$PROJECT_DIR" status --porcelain --untracked-files=all -- "$@" 2>/dev/null \
    | cut -c4- | sed 's/.* -> //'
}

# needs_run <files> <test pattern> → success when some file is not a test.
needs_run() {
  [[ -n "$1" ]] || return 1
  printf '%s\n' "$1" | grep -qvE -e "$2"
}

FAILURES=""
NOT_RUN=""

while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  NAME=$(printf '%s' "$suite" | jq -r '.name // "Tests"')
  TESTS_PATTERN=$(printf '%s' "$suite" | jq -r '.tests_pattern // "^$"')
  CWD=$(printf '%s' "$suite" | jq -r '.cwd // "."')
  RUNNER=$(printf '%s' "$suite" | jq -r '.runner // empty')
  HINT=$(printf '%s' "$suite" | jq -r '.missing_hint // "falta su ejecutable"')
  WATCH=()
  while IFS= read -r path; do [[ -n "$path" ]] && WATCH+=("$path"); done \
    < <(printf '%s' "$suite" | jq -r '(.watch // [])[]')
  ARGS=()
  while IFS= read -r arg; do ARGS+=("$arg"); done \
    < <(printf '%s' "$suite" | jq -r '(.args // [])[]')
  [[ ${#WATCH[@]} -gt 0 && -n "$RUNNER" ]] || continue

  FILES=$(changed "${WATCH[@]}")
  needs_run "$FILES" "$TESTS_PATTERN" || continue

  DIR="$PROJECT_DIR/$CWD"
  RUNNER_PATH=$RUNNER
  [[ "$RUNNER" == */* && "$RUNNER" != /* ]] && RUNNER_PATH="$DIR/$RUNNER"
  if [[ -x "$RUNNER_PATH" ]] || { [[ "$RUNNER" != */* ]] && command -v "$RUNNER" >/dev/null 2>&1; }; then
    if ! OUT=$(cd "$DIR" && "$RUNNER_PATH" ${ARGS[@]+"${ARGS[@]}"} 2>&1); then
      FAILURES+=$'\n\n'"$NAME, \`${RUNNER##*/} ${ARGS[*]-}\`:"$'\n'"$(printf '%s' "$OUT" | tail -30)"
    fi
  else
    NOT_RUN+=" No se corrieron los tests de $NAME: $HINT."
  fi
done < <(printf '%s' "$CONFIG" | jq -c '(.suites // [])[]' 2>/dev/null)

if [[ -n "$FAILURES" && "$SECOND_ATTEMPT" == "true" ]]; then
  warn "El turno cerró con la suite en rojo: el asistente no la pudo poner en verde después del primer aviso. Revisalo antes de seguir.${NOT_RUN}${FAILURES}"
fi
if [[ -n "$FAILURES" ]]; then
  block "La suite falla y el turno todavía no se cierra. Implementá lo mínimo para que pase; nunca modifiques, deshabilites ni borres un test para lograrlo$(ref tests).${NOT_RUN}${FAILURES}"
fi
if [[ -n "$NOT_RUN" ]]; then
  warn "${NOT_RUN# }"
fi

finish
