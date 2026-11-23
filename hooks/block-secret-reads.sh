#!/usr/bin/env bash
# PreToolUse (Read, Grep) — no secret or credential file enters the model's context.
# Secrets live only in environment variables.
#
# Grep shows the lines it matches, so a Grep over a secret file reads it. Only the
# path it is given is checked: a Grep over a folder is left to the project's
# permissions.deny, which Claude Code applies to every tool that reads files.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INPUT=$(cat)
FILE=$(field "$INPUT" '.tool_input.file_path // .tool_input.path')
[[ -n "$FILE" ]] || finish

if is_secret_path "$FILE"; then
  deny "Lectura bloqueada: $(relative "$FILE") tiene secretos o credenciales, y no se cargan en el contexto del modelo$(ref secrets). Si necesitás saber qué variables existen, leé .env.example."
fi

finish
