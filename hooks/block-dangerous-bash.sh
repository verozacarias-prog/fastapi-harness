#!/usr/bin/env bash
# PreToolUse (Bash) — the rules a shell command can break. What the project
# writes for its assistant is read by the model; this is run by code.
#
# It reads the text of the command: it stops what an assistant would run in the
# normal course of work, not a command built to slip past it.
# Every rule that rejects runs before any rule that asks. The rules of one project
# (bash_rules in its configuration) go after the plugin's own, in the same order.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT=$(cat)
COMMAND=$(field "$INPUT" '.tool_input.command')
[[ -n "$COMMAND" ]] || finish

# The rules read the command without the text that cannot run (a commit message,
# the body of a heredoc written to a file): inert-text.awk says which. If that
# copy cannot be made, or the command is longer than 32 KB, they read the command
# as it came.
if (( $(printf '%s' "$COMMAND" | LC_ALL=C wc -c) <= 32768 )); then
  INERT_FREE=$(printf '%s' "$COMMAND" | LC_ALL=C awk -f "$(dirname "${BASH_SOURCE[0]}")/inert-text.awk" 2>/dev/null) \
    && [[ -n "$INERT_FREE" ]] && COMMAND=$INERT_FREE
fi

matches() { printf '%s' "$COMMAND" | grep -qE -e "$1"; }

# Git is read in a normalized copy of the command:
#   - quoted text becomes Q, so a commit message that mentions "-n" or "--force"
#     is not taken for the flag itself;
#   - the global options between git and its subcommand (-C <dir>, -c <k=v>,
#     --git-dir …, --no-pager…) are dropped, so "git -C . push" is a push.
# Short flags can come together (-fu, -anm); a value-taking flag (-m, -o) ends
# the group, so what follows it is its value, not more flags.
UNQUOTED=$(printf '%s' "$COMMAND" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g")
unquoted_matches() { printf '%s' "$UNQUOTED" | grep -qE -e "$1"; }
GIT=$UNQUOTED
while :; do
  NEXT=$(printf '%s' "$GIT" | sed -E \
    's/(^|[^[:alnum:]_-])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|config-env)[[:space:]]+[^-[:space:]][^[:space:]]*|--[a-z-]+(=[^[:space:]]+)?|-P)/\1git/g')
  [[ "$NEXT" == "$GIT" ]] && break
  GIT=$NEXT
done
git_matches() { printf '%s' "$GIT" | grep -qE -e "$1"; }

# Start of a command: beginning of the line, after a separator or after a
# backtick, which opens a command substitution.
S='(^|[;&|(`][[:space:]]*|[[:space:]])'

# A test file: inside a test directory, or named like one (configuration: tests).
escape_regex() { printf '%s' "$1" | sed -E 's/[][\.*^$()+?{}|]/\\&/g'; }
TEST_PATH=""
while IFS= read -r dir; do
  [[ -n "$dir" ]] && TEST_PATH+="${TEST_PATH:+|}$(escape_regex "${dir%/}/")"
done < <(cfg_list .tests.dirs)
TEST_FILE_PATTERN=$(cfg .tests.file_pattern)
[[ -n "$TEST_FILE_PATTERN" ]] && TEST_PATH+="${TEST_PATH:+|}[^[:space:]]*${TEST_FILE_PATTERN}([[:space:]]|\$)"
[[ -n "$TEST_PATH" ]] && TEST_PATH="($TEST_PATH)"

# project_rules <deny|ask> → applies the project's own rules of that kind.
project_rules() {
  local rule pattern message
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    pattern=$(printf '%s' "$rule" | jq -r '.pattern // empty')
    message=$(printf '%s' "$rule" | jq -r '.message // empty')
    [[ -n "$pattern" ]] || continue
    if matches "$pattern"; then
      "$1" "${message:-Este comando lo frena una regla del proyecto: $pattern}"
    fi
  done < <(printf '%s' "$CONFIG" | jq -c "(.bash_rules.$1 // [])[]" 2>/dev/null)
}

# ── Rejected ─────────────────────────────────────────────────────────────────

# 1. Recursive deletion, device destruction and wide-open permissions.
#    Deleting one file with rm or rm -f is not mass deletion.
if matches "${S}rm[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(-[a-zA-Z]*[rR]|--recursive)|${S}mkfs|${S}dd[[:space:]]+if=|:\(\)\{.*\};:"; then
  deny "Comando destructivo bloqueado: $COMMAND"
fi
if matches "${S}chmod[[:space:]]+(-R[[:space:]]+)?777"; then
  deny "chmod 777 bloqueado: abre el archivo a cualquier usuario del sistema."
fi

# 2. Reading a secrets file through the shell (the Read tool has its own hook).
#    The same rule as the Read hook, on every word that looks like a file: it has
#    a dot or a slash, so a bare word like "credentials" in a grep stays free.
#    A reading command also counts right after a quote, as in bash -c "cat …" or
#    ssh host 'cat …', where another shell runs it.
if matches "(${S}|[\"'])(cat|less|more|head|tail|grep|rg|bat|nl|awk|sed|xxd|strings|base64|cp|scp|diff|source|\.)[[:space:]]"; then
  while IFS= read -r token; do
    if [[ "$token" == *[./]* ]] && is_secret_path "$token"; then
      deny "Lectura bloqueada: $token tiene secretos o credenciales y no se carga en el contexto del modelo$(ref secrets). Si necesitás saber qué variables existen, leé .env.example."
    fi
  done < <(printf '%s' "$COMMAND" | grep -oE "[^[:space:]\"'\`;|&<>()]+")
fi

# 3. History rewriting and force push, in any of its forms.
if git_matches "${S}git[[:space:]]+push([[:space:]].*)?[[:space:]](--force|-[a-np-zA-Z]*f|\+[^[:space:]])"; then
  deny "El push forzado (--force, --force-with-lease, -f o +rama) no está permitido: lo hace una persona o no se hace."
fi
if git_matches "${S}git[[:space:]]+filter-branch"; then
  deny "git filter-branch reescribe la historia: lo hace una persona o no se hace."
fi

# 4. Skipping the pre-commit hook, and merging.
if git_matches "${S}git[[:space:]]+commit([[:space:]].*)?[[:space:]](--no-verify([[:space:]]|$)|-[a-ln-zA-Z]*n)"; then
  deny "git commit --no-verify saltea el hook de pre-commit y sus controles. Saltearlo lo decide una persona, a mano$(ref verify commit)."
fi
if matches "${S}gh[[:space:]]+pr[[:space:]]+merge" || matches "${S}gh[[:space:]]+api[[:space:]].*/merge([^[:alnum:]_-]|$)"; then
  deny "Un asistente nunca hace merge: la aprobación final de un pull request es de una persona$(ref commit)."
fi

# 5. Production. Naming the word, as in a grep, is not operating on it: what
#    counts is an environment set to it (APP_ENV=production, --env production),
#    outside quotes.
if unquoted_matches '(ENV|env)(=|[[:space:]]+)production([^[:alnum:]_-]|$)'; then
  deny "Ningún asistente opera contra production: lo aprueba y lo hace una persona."
fi

# 6. The project's own rules that reject.
project_rules deny

# ── Asked ────────────────────────────────────────────────────────────────────

# 7. Deleting or rewriting a test from the shell: the same rule as the edit hook.
#    Each rule stays inside one command: it does not cross ; & or |.
if [[ -n "$TEST_PATH" ]] && {
  matches "${S}(rm|unlink|mv)[[:space:]][^;&|]*${TEST_PATH}" \
    || matches "${S}(sed|perl)[[:space:]]([^;&|]*[[:space:]])?-[a-zA-Z]*i[^;&|]*${TEST_PATH}" \
    || matches ">[[:space:]]*${TEST_PATH}" \
    || git_matches "${S}git[[:space:]]+(checkout|restore|rm)[[:space:]][^;&|]*${TEST_PATH}"
}; then
  ask "Este comando borra o cambia un test. Un test no se modifica, no se deshabilita y no se borra sin la aprobación de una persona$(ref tests). Confirmá solo si la persona lo decidió."
fi

# 8. Discarding local work.
if git_matches "${S}git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f)"; then
  ask "Este comando descarta trabajo local sin vuelta atrás. Confirmalo a mano."
fi

# 9. Commits and pushes belong to the person.
if git_matches "${S}git[[:space:]]+commit([[:space:]]|$)" && ! matches '--dry-run'; then
  ask "Un asistente hace commit solo cuando una persona se lo pide$(ref commit). Confirmá que te lo pidieron."
fi
if git_matches "${S}git[[:space:]]+push([[:space:]]|$)" && ! matches '--dry-run'; then
  ask "Un asistente hace push solo cuando una persona se lo pide$(ref commit). Confirmá que te lo pidieron."
fi

# 10. New dependencies. Installing from a requirements file stays free.
if { matches "${S}pip3?[[:space:]]+install([[:space:]]|$)" && ! matches '[[:space:]](-r|--requirement)[[:space:]]'; } \
  || matches "${S}(npm|pnpm|yarn|bun)[[:space:]]+(i|add|install)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]]"; then
  HINT=$(cfg .dependency_hint)
  ask "Vas a instalar una dependencia. Verificá en el registro oficial que el paquete existe y es el correcto, y justificá por qué no alcanza lo instalado$(ref dependencies).${HINT:+ $HINT}"
fi

# 11. The project's own rules that ask.
project_rules ask

finish
