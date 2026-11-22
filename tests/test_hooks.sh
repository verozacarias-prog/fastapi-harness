#!/usr/bin/env bash
# Tests for the hooks of the plugin, in hooks/.
#
# Each case feeds a hook the JSON that Claude Code would send it and checks the
# decision: allow, ask, deny (PreToolUse) or block (Stop). The hooks run against
# throwaway git repositories, so nothing here touches a real project:
#   - a project with its own .claude/fastapi-harness.json, laid out like a backend
#     plus a dashboard (the H cases);
#   - a project without one, laid out like a plain FastAPI service (the C cases).
#
# Usage: bash tests/test_hooks.sh
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS="$ROOT/hooks"
PASSED=0
FAILED=0

command -v jq >/dev/null 2>&1 || { echo "test_hooks: jq is required"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test_hooks: git is required"; exit 1; }

SANDBOX=$(mktemp -d)
PLAIN=$(mktemp -d)
trap 'rm -rf "$SANDBOX" "$PLAIN"' EXIT
export CLAUDE_PROJECT_DIR="$SANDBOX"
unset HARNESS_ALLOW_RED

# ── Helpers ──────────────────────────────────────────────────────────────────

# decision <hook file> <json> → allow | ask | deny | block | error-<status>
decision() {
  local out status d
  out=$(printf '%s' "$2" | bash "$HOOKS/$1" 2>/dev/null)
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "error-$status"
    return
  fi
  d=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // .decision // empty' 2>/dev/null)
  echo "${d:-allow}"
}

expect() {
  local name=$1 want=$2 got=$3
  if [[ "$got" == "$want" ]]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "FAIL $name: expected $want, got $got"
  fi
}

read_json() { jq -n --arg p "$1" '{tool_name: "Read", tool_input: {file_path: $p}}'; }
edit_json() {
  jq -n --arg p "$1" --arg o "$2" --arg n "$3" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}'
}
write_json() {
  jq -n --arg p "$1" --arg c "$2" '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}'
}
bash_json() { jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'; }
stop_json() { jq -n --argjson a "${1:-false}" '{hook_event_name: "Stop", stop_hook_active: $a}'; }

# warning <hook file> <json> → the message the hook shows the person, or nothing.
warning() {
  printf '%s' "$2" | bash "$HOOKS/$1" 2>/dev/null | jq -r '.systemMessage // empty' 2>/dev/null
}
# reason <hook file> <json> → the reason the hook gives the assistant, or nothing.
reason() {
  printf '%s' "$2" | bash "$HOOKS/$1" 2>/dev/null \
    | jq -r '.reason // .hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}
# mentions <text> <pattern> → yes | no
mentions() { printf '%s' "$1" | grep -qE -e "$2" && echo yes || echo no; }

# Suite stubs: each one leaves a mark when it runs and fails if its red flag exists.
reset_marks() { rm -f "$SANDBOX"/.backend-ran "$SANDBOX"/.frontend-ran "$SANDBOX"/.backend-red "$SANDBOX"/.frontend-red; }
ran() { [[ -f "$SANDBOX/.$1-ran" ]] && echo yes || echo no; }
restore_tree() { git -C "$SANDBOX" checkout -q -- . && git -C "$SANDBOX" clean -qfd -e '.backend-*' -e '.frontend-*'; }

# ── Sandbox ──────────────────────────────────────────────────────────────────

S="$SANDBOX"
mkdir -p "$S/backend/app" "$S/backend/tests/unit" "$S/backend/migrations/versions" \
  "$S/backend/.venv/bin" "$S/docs/features/FEAT-003" "$S/frontend/src" "$S/frontend/node_modules/.bin"

printf 'def service() -> int:\n    return 1\n' > "$S/backend/app/service.py"
printf 'def test_a() -> None:\n    assert 1 == 1\n' > "$S/backend/tests/unit/test_service.py"
printf 'revision = "0001"\n' > "$S/backend/migrations/versions/0001_init.py"
printf '# FEAT-003\n\n- C1-01: un caso\n- **Aprobado por:** pendiente\n' > "$S/docs/features/FEAT-003/spec.md"
printf 'export const Page = () => null;\n' > "$S/frontend/src/Page.tsx"
printf 'it("renders", () => {});\n' > "$S/frontend/src/Page.test.tsx"
printf 'APP_ENV=local\n' > "$S/.env.example"
printf 'APP_ENV=local\n' > "$S/backend/app/constants.py"
mkdir -p "$S/frontend/e2e" "$S/otra/carpeta"
printf 'POSTGRES_USER=app\n' > "$S/frontend/e2e/compose.env"

cat > "$S/backend/.venv/bin/python" <<'STUB'
#!/bin/sh
touch "$CLAUDE_PROJECT_DIR/.backend-ran"
if [ -f "$CLAUDE_PROJECT_DIR/.backend-red" ]; then echo "FAILED tests/unit/test_service.py::test_a"; exit 1; fi
echo "1 passed"
STUB
cat > "$S/frontend/node_modules/.bin/vitest" <<'STUB'
#!/bin/sh
touch "$CLAUDE_PROJECT_DIR/.frontend-ran"
if [ -f "$CLAUDE_PROJECT_DIR/.frontend-red" ]; then echo "FAIL src/Page.test.tsx > renders"; exit 1; fi
echo "1 passed"
STUB
chmod +x "$S/backend/.venv/bin/python" "$S/frontend/node_modules/.bin/vitest"
printf '.backend-*\n.frontend-*\n.worker-*\n.env\n.env.*\n!.env.example\n' > "$S/.gitignore"
mkdir -p "$S/.claude"
cp "$ROOT/tests/fixtures/project-config.json" "$S/.claude/fastapi-harness.json"

git -C "$S" init -q
git -C "$S" -c user.name=test -c user.email=test@example.invalid add -A
git -C "$S" -c user.name=test -c user.email=test@example.invalid commit -q -m init

# ── Hook 1: block-secret-reads.sh ────────────────────────────────────────────

H=block-secret-reads.sh
expect "H1-1 .env"             deny  "$(decision $H "$(read_json "$S/.env")")"
expect "H1-1 backend/.env.local" deny "$(decision $H "$(read_json "$S/backend/.env.local")")"
expect "H1-2 .env.example"     allow "$(decision $H "$(read_json "$S/.env.example")")"
expect "H1-3 constants.py"     allow "$(decision $H "$(read_json "$S/backend/app/constants.py")")"
expect "H1-4 e2e compose.env"  allow "$(decision $H "$(read_json "$S/frontend/e2e/compose.env")")"
expect "H1-5 other compose.env" deny "$(decision $H "$(read_json "$S/otra/carpeta/compose.env")")"

# ── Hook 2: protect-tests-and-specs.sh ───────────────────────────────────────

H=protect-tests-and-specs.sh
TEST_FILE="$S/backend/tests/unit/test_service.py"
SPEC_FILE="$S/docs/features/FEAT-003/spec.md"

expect "H2-1 new test file" allow \
  "$(decision $H "$(write_json "$S/backend/tests/unit/test_new.py" 'def test_new() -> None: ...')")"
expect "H2-2 append to an existing test" allow \
  "$(decision $H "$(edit_json "$TEST_FILE" '    assert 1 == 1
' '    assert 1 == 1


def test_b() -> None:
    assert 2 == 2
')")"
expect "H2-3 change an assertion" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'assert 1 == 1' 'assert 1 == 2')")"
expect "H2-4 overwrite an existing test" ask \
  "$(decision $H "$(write_json "$TEST_FILE" 'def test_a() -> None: ...')")"
expect "H2-5 fill in the approval line" deny \
  "$(decision $H "$(edit_json "$SPEC_FILE" '- **Aprobado por:** pendiente' '- **Aprobado por:** Una Persona 19/11/2026')")"
expect "H2-6 add cases, approval still pending" allow \
  "$(decision $H "$(edit_json "$SPEC_FILE" '- **Aprobado por:** pendiente' '- C1-02: otro caso
- **Aprobado por:** pendiente')")"
expect "H2-7 edit a versioned migration" ask \
  "$(decision $H "$(edit_json "$S/backend/migrations/versions/0001_init.py" '"0001"' '"0001b"')")"
expect "H2-8 new migration" allow \
  "$(decision $H "$(write_json "$S/backend/migrations/versions/0002_more.py" 'revision = "0002"')")"
expect "H2-9 edit .env" deny \
  "$(decision $H "$(edit_json "$S/.env" 'A=1' 'A=2')")"
expect "H2-9 path with .." deny \
  "$(decision $H "$(write_json "$S/backend/../../outside.py" 'x = 1')")"

FRONT_TEST="$S/frontend/src/Page.test.tsx"
expect "H2-10 add @pytest.mark.skip" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'def test_a' '@pytest.mark.skip
def test_a')")"
expect "H2-11 it.skip" ask \
  "$(decision $H "$(edit_json "$FRONT_TEST" 'it(' 'it.skip(')")"
expect "H2-11 it.only" ask \
  "$(decision $H "$(edit_json "$FRONT_TEST" 'it(' 'it.only(')")"
expect "H2-11 add @pytest.mark.xfail" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'def test_a' '@pytest.mark.xfail
def test_a')")"
expect "H2-11 add pytest.skip()" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" '    assert 1 == 1' '    pytest.skip("later")
    assert 1 == 1')")"
expect "H2-12 append inside a line" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'assert 1 == 1' 'assert 1 == 1 or True')")"
expect "H2-13 append a whole test function" allow \
  "$(decision $H "$(edit_json "$TEST_FILE" 'def test_a() -> None:
    assert 1 == 1' 'def test_a() -> None:
    assert 1 == 1


def test_d() -> None:
    assert 4 == 4')")"
expect "H2-14 Write keeps the content and adds a test" allow \
  "$(decision $H "$(write_json "$TEST_FILE" "$(cat "$TEST_FILE")

def test_e() -> None:
    assert 5 == 5")")"
expect "H2-15 Write removes a line" ask \
  "$(decision $H "$(write_json "$TEST_FILE" 'def test_a() -> None:')")"
expect "H2-16 module-level pytestmark skip" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'def test_a' 'pytestmark = pytest.mark.skip(reason="later")


def test_a')")"
expect "H2-16 @mark.skip after from pytest import mark" ask \
  "$(decision $H "$(edit_json "$TEST_FILE" 'def test_a' '@mark.skip
def test_a')")"
expect "H2-17 edit a hook" ask \
  "$(decision $H "$(edit_json "$S/.claude/hooks/lib.sh" 'exit 0' 'exit 1')")"
expect "H2-17 edit settings.json" ask \
  "$(decision $H "$(edit_json "$S/.claude/settings.json" '{}' '{"hooks": {}}')")"
expect "H2-17 write settings.local.json" ask \
  "$(decision $H "$(write_json "$S/.claude/settings.local.json" '{"env": {"HARNESS_ALLOW_RED": "1"}}')")"

# ── Hook 3: verify-tests-on-stop.sh ──────────────────────────────────────────

H=verify-tests-on-stop.sh

reset_marks
expect "H3-1 clean tree" allow "$(decision $H "$(stop_json)")"
expect "H3-1 pytest did not run" no "$(ran backend)"
expect "H3-1 vitest did not run" no "$(ran frontend)"

reset_marks; restore_tree
printf '\n# changed\n' >> "$S/backend/app/service.py"
expect "H3-2 backend change, green" allow "$(decision $H "$(stop_json)")"
expect "H3-2 pytest ran" yes "$(ran backend)"

reset_marks; touch "$S/.backend-red"
expect "H3-3 backend change, red" block "$(decision $H "$(stop_json)")"

reset_marks; restore_tree; touch "$S/.backend-red"
printf '\ndef test_c() -> None:\n    assert False\n' >> "$TEST_FILE"
expect "H3-4 only backend tests changed, red" allow "$(decision $H "$(stop_json)")"

reset_marks; restore_tree; touch "$S/.backend-red"
printf '\n# changed\n' >> "$S/backend/app/service.py"
expect "H3-5 HARNESS_ALLOW_RED=1" allow \
  "$(HARNESS_ALLOW_RED=1 decision $H "$(stop_json)")"
expect "H3-5 pytest did not run" no "$(ran backend)"

reset_marks; touch "$S/.backend-red"
expect "H3-6 stop_hook_active" allow "$(decision $H "$(stop_json true)")"

reset_marks; restore_tree; touch "$S/.frontend-red"
printf '\n// changed\n' >> "$S/frontend/src/Page.tsx"
expect "H3-7 frontend change, red" block "$(decision $H "$(stop_json)")"

reset_marks; restore_tree; touch "$S/.frontend-red"
printf '\nit("fails", () => { throw new Error(); });\n' >> "$S/frontend/src/Page.test.tsx"
expect "H3-8 only frontend tests changed, red" allow "$(decision $H "$(stop_json)")"

reset_marks; restore_tree
printf '\n# changed\n' >> "$S/backend/app/service.py"
decision $H "$(stop_json)" >/dev/null
expect "H3-9 backend only: vitest did not run" no "$(ran frontend)"

reset_marks; restore_tree
printf '\n// changed\n' >> "$S/frontend/src/Page.tsx"
decision $H "$(stop_json)" >/dev/null
expect "H3-9 frontend only: pytest did not run" no "$(ran backend)"

reset_marks; restore_tree; touch "$S/.backend-red"
printf 'def helper() -> int:\n    return 2\n' > "$S/backend/app/new_module.py"
expect "H3-10 new file not yet added to git, red" block "$(decision $H "$(stop_json)")"
expect "H3-10 pytest ran" yes "$(ran backend)"

reset_marks; restore_tree; touch "$S/.backend-red"
printf '\n# changed\n' >> "$S/backend/app/service.py"
expect "H3-11 second attempt, red: does not block" allow "$(decision $H "$(stop_json true)")"
expect "H3-11 second attempt, red: warns the person" yes \
  "$(mentions "$(warning $H "$(stop_json true)")" 'rojo')"

reset_marks
expect "H3-12 second attempt, green: no warning" "" "$(warning $H "$(stop_json true)")"

reset_marks; restore_tree
mv "$S/backend/.venv" "$S/backend/.venv-aside"
printf '\n# changed\n' >> "$S/backend/app/service.py"
expect "H3-13 no backend/.venv: does not block" allow "$(decision $H "$(stop_json)")"
expect "H3-13 no backend/.venv: warns" yes \
  "$(mentions "$(warning $H "$(stop_json)")" 'backend/\.venv')"
mv "$S/backend/.venv-aside" "$S/backend/.venv"

reset_marks; restore_tree
mv "$S/frontend/node_modules" "$S/frontend/node_modules-aside"
printf '\n// changed\n' >> "$S/frontend/src/Page.tsx"
expect "H3-14 no vitest: does not block" allow "$(decision $H "$(stop_json)")"
expect "H3-14 no vitest: warns" yes \
  "$(mentions "$(warning $H "$(stop_json)")" 'node_modules')"
mv "$S/frontend/node_modules-aside" "$S/frontend/node_modules"

reset_marks; restore_tree; touch "$S/.backend-red"
mv "$S/frontend/node_modules" "$S/frontend/node_modules-aside"
printf '\n# changed\n' >> "$S/backend/app/service.py"
printf '\n// changed\n' >> "$S/frontend/src/Page.tsx"
expect "H3-15 backend red, frontend cannot run: blocks" block "$(decision $H "$(stop_json)")"
H3_15_REASON=$(reason $H "$(stop_json)")
expect "H3-15 the reason names the failure" yes "$(mentions "$H3_15_REASON" 'FAILED')"
expect "H3-15 the reason names what did not run" yes "$(mentions "$H3_15_REASON" 'node_modules')"
mv "$S/frontend/node_modules-aside" "$S/frontend/node_modules"

reset_marks; restore_tree

# ── Hook 4: block-dangerous-bash.sh ──────────────────────────────────────────

H=block-dangerous-bash.sh
expect "H4-1 rm -rf"              deny  "$(decision $H "$(bash_json 'rm -rf backend')")"
expect "H4-2 git push --force"    deny  "$(decision $H "$(bash_json 'git push --force')")"
expect "H4-2 git push -f"         deny  "$(decision $H "$(bash_json 'git push -f origin x')")"
expect "H4-3 commit --no-verify"  deny  "$(decision $H "$(bash_json 'git commit -m "x" --no-verify')")"
expect "H4-4 git commit"          ask   "$(decision $H "$(bash_json 'git commit -m "x"')")"
expect "H4-5 gh pr merge"         deny  "$(decision $H "$(bash_json 'gh pr merge 215')")"
expect "H4-6 evals --run"         ask   "$(decision $H "$(bash_json 'python -m evals.classification.run --run')")"
expect "H4-6 evals without --run" allow "$(decision $H "$(bash_json 'python -m evals.classification.run')")"
expect "H4-7 pip install pkg"     ask   "$(decision $H "$(bash_json 'pip install httpx')")"
expect "H4-7 pip install -r"      allow "$(decision $H "$(bash_json 'pip install -r requirements-dev.txt')")"
expect "H4-8 cat .env"            deny  "$(decision $H "$(bash_json 'cat .env')")"
expect "H4-9 git status"          allow "$(decision $H "$(bash_json 'git status')")"
expect "H4-9 pytest"              allow "$(decision $H "$(bash_json 'pytest')")"
expect "H4-9 ruff check"          allow "$(decision $H "$(bash_json 'ruff check .')")"
expect "H4-10 cat id_rsa"         deny  "$(decision $H "$(bash_json 'cat ~/.ssh/id_rsa')")"
expect "H4-11 cat a .pem"         deny  "$(decision $H "$(bash_json 'cat certs/server.pem')")"
expect "H4-12 head credentials"   deny  "$(decision $H "$(bash_json 'head credentials.json')")"
expect "H4-13 cat e2e compose.env" allow "$(decision $H "$(bash_json 'cat frontend/e2e/compose.env')")"
expect "H4-14 -n inside the message" ask \
  "$(decision $H "$(bash_json 'git commit -m "docs: quitar el -n del ejemplo"')")"
expect "H4-15 git commit -n"      deny  "$(decision $H "$(bash_json 'git commit -n -m "x"')")"
expect "H4-16 rm -f one file"     allow "$(decision $H "$(bash_json 'rm -f build.log')")"
expect "H4-17 rm -r"              deny  "$(decision $H "$(bash_json 'rm -r carpeta')")"
expect "H4-17 rm -rf"             deny  "$(decision $H "$(bash_json 'rm -rf carpeta')")"
expect "H4-18 --env production"   deny  "$(decision $H "$(bash_json 'render services --env production')")"
expect "H4-18 --env=production"   deny  "$(decision $H "$(bash_json 'render services --env=production')")"
expect "H4-19 grep production"    allow "$(decision $H "$(bash_json 'grep -rn production docs/')")"
expect "H4-20 git -C commit -n"   deny  "$(decision $H "$(bash_json 'git -C . commit -n -m x')")"
expect "H4-20 git -c commit --no-verify" deny \
  "$(decision $H "$(bash_json 'git -c core.hooksPath=/dev/null commit --no-verify -m x')")"
expect "H4-21 git -C commit"      ask   "$(decision $H "$(bash_json 'git -C . commit -m x')")"
expect "H4-21 git -C push"        ask   "$(decision $H "$(bash_json 'git -C /ruta/al/repo push')")"
expect "H4-22 git -C push --force" deny "$(decision $H "$(bash_json 'git -C . push --force origin x')")"
expect "H4-22 --force-with-lease" deny  "$(decision $H "$(bash_json 'git push --force-with-lease')")"
expect "H4-22 push +branch"       deny  "$(decision $H "$(bash_json 'git push origin +rama')")"
expect "H4-23 gh api merge"       deny  "$(decision $H "$(bash_json 'gh api -X PUT repos/o/r/pulls/1/merge')")"
expect "H4-24 rm a backend test"  ask   "$(decision $H "$(bash_json 'rm backend/tests/unit/test_x.py')")"
expect "H4-24 rm -f a dashboard test" ask "$(decision $H "$(bash_json 'rm -f frontend/src/A.test.tsx')")"
expect "H4-25 sed -i a test"      ask   "$(decision $H "$(bash_json "sed -i '' 's/a/b/' backend/tests/x.py")")"
expect "H4-25 git checkout tests" ask   "$(decision $H "$(bash_json 'git checkout -- backend/tests/')")"
expect "H4-26 rm -f build.log"    allow "$(decision $H "$(bash_json 'rm -f build.log')")"
expect "H4-27 git push -fu"       deny  "$(decision $H "$(bash_json 'git push -fu origin x')")"
expect "H4-27 git push -uf"       deny  "$(decision $H "$(bash_json 'git push -uf origin x')")"
expect "H4-28 git commit -nm"     deny  "$(decision $H "$(bash_json 'git commit -nm wip')")"
expect "H4-28 git commit -anm"    deny  "$(decision $H "$(bash_json 'git commit -anm wip')")"
expect "H4-28 git commit -am"     ask   "$(decision $H "$(bash_json 'git commit -am "x"')")"
expect "H4-29 checkout && pytest tests" allow \
  "$(decision $H "$(bash_json 'git checkout main && pytest backend/tests/unit -q')")"
expect "H4-29 mv && pytest tests" allow \
  "$(decision $H "$(bash_json 'mv a.txt b.txt && pytest backend/tests/unit')")"
expect "H4-29 rm -f && vitest a test" allow \
  "$(decision $H "$(bash_json 'rm -f build.log && npx vitest run src/App.test.tsx')")"
expect "H4-29 rm a test after &&" ask \
  "$(decision $H "$(bash_json 'ls && rm backend/tests/unit/test_x.py')")"
expect "H4-30 grep a quoted APP_ENV=production" allow \
  "$(decision $H "$(bash_json 'grep -n "APP_ENV=production" docs/operacion.md')")"
expect "H4-30 APP_ENV=production uvicorn" deny \
  "$(decision $H "$(bash_json 'APP_ENV=production uvicorn app.main:app')")"
expect "H4-31 git --git-dir .git push --force" deny \
  "$(decision $H "$(bash_json 'git --git-dir .git push --force')")"
expect "H4-32 sed -i.bak" allow   "$(decision $H "$(bash_json "sed -i.bak 's/a/b/' x.py")")"
expect "H4-32 sed -i.bak writes no errors" "" \
  "$(bash_json "sed -i.bak 's/a/b/' x.py" | bash "$HOOKS/$H" 2>&1 >/dev/null)"

# ── Configuration (proposal 0001, cases C-1 to C-13) ─────────────────────────

# C-5 to C-7 and C-9 to C-11 run in the project with its own configuration.
H=block-dangerous-bash.sh
EVALS='python -m evals.classification.run --run'
expect "C-5 configured ask rule" ask "$(decision $H "$(bash_json "$EVALS")")"
expect "C-5 with the configured message" yes \
  "$(mentions "$(reason $H "$(bash_json "$EVALS")")" 'set de regresión')"
expect "C-6 configured deny rule" deny "$(decision $H "$(bash_json 'render deploys create srv-1')")"

H=block-secret-reads.sh
expect "C-7 rule reference in the message" yes \
  "$(mentions "$(reason $H "$(read_json "$S/.env")")" 'AGENTS\.md § 7')"

H=verify-tests-on-stop.sh
reset_marks; restore_tree
rm -f "$S"/.worker-ran "$S"/.worker-red
mkdir -p "$S/worker/.venv/bin" "$S/worker/jobs"
cat > "$S/worker/.venv/bin/python" <<'STUB'
#!/bin/sh
touch "$CLAUDE_PROJECT_DIR/.worker-ran"
if [ -f "$CLAUDE_PROJECT_DIR/.worker-red" ]; then echo "FAILED jobs/test_job.py::test_job"; exit 1; fi
echo "1 passed"
STUB
chmod +x "$S/worker/.venv/bin/python"
jq '.suites += [{name: "Worker", watch: ["worker/jobs"], tests_pattern: "^worker/jobs/test_",
  cwd: "worker", runner: ".venv/bin/python", args: ["-m", "pytest", "-q"], missing_hint: "falta worker/.venv"}]' \
  "$S/.claude/fastapi-harness.json" > "$SANDBOX.cfg" && mv "$SANDBOX.cfg" "$S/.claude/fastapi-harness.json"
printf 'def job() -> int:\n    return 1\n' > "$S/worker/jobs/job.py"
touch "$S/.worker-red"
expect "C-9 third suite, red" block "$(decision $H "$(stop_json)")"
expect "C-9 the third suite ran" yes "$([[ -f "$S/.worker-ran" ]] && echo yes || echo no)"
expect "C-9 backend did not run" no "$(ran backend)"
expect "C-9 dashboard did not run" no "$(ran frontend)"
rm -rf "$S/worker" "$S"/.worker-ran "$S"/.worker-red
reset_marks; restore_tree

touch "$S/.backend-red"
printf '\n# changed\n' >> "$S/backend/app/service.py"
expect "C-10 HARNESS_ALLOW_RED=1" allow "$(HARNESS_ALLOW_RED=1 decision $H "$(stop_json)")"
expect "C-10 no suite ran" no "$(ran backend)"
reset_marks; restore_tree

H=protect-tests-and-specs.sh
expect "C-11 edit the project configuration" ask \
  "$(decision $H "$(edit_json "$S/.claude/fastapi-harness.json" '"develop"' '"main"')")"

# The plain project: a FastAPI service without .claude/fastapi-harness.json.
P="$PLAIN"
export CLAUDE_PROJECT_DIR="$P"
mkdir -p "$P/app" "$P/tests" "$P/alembic/versions" "$P/.venv/bin"
printf 'def service() -> int:\n    return 1\n' > "$P/app/service.py"
printf 'def test_a() -> None:\n    assert 1 == 1\n' > "$P/tests/test_x.py"
printf 'revision = "0001"\n' > "$P/alembic/versions/0001_init.py"
cat > "$P/.venv/bin/python" <<'STUB'
#!/bin/sh
touch "$CLAUDE_PROJECT_DIR/.backend-ran"
if [ -f "$CLAUDE_PROJECT_DIR/.backend-red" ]; then echo "FAILED tests/test_x.py::test_a"; exit 1; fi
echo "1 passed"
STUB
chmod +x "$P/.venv/bin/python"
printf '.backend-*\n.venv/\n.env\n' > "$P/.gitignore"
git -C "$P" init -q
git -C "$P" -c user.name=test -c user.email=test@example.invalid add -A
git -C "$P" -c user.name=test -c user.email=test@example.invalid commit -q -m init

H=protect-tests-and-specs.sh
expect "C-1 default tests dir" ask \
  "$(decision $H "$(edit_json "$P/tests/test_x.py" 'assert 1 == 1' 'assert 1 == 2')")"
expect "C-2 default migrations dir" ask \
  "$(decision $H "$(edit_json "$P/alembic/versions/0001_init.py" '"0001"' '"0001b"')")"

H=verify-tests-on-stop.sh
touch "$P/.backend-red"
printf '\n# changed\n' >> "$P/app/service.py"
expect "C-3 default suite, red" block "$(decision $H "$(stop_json)")"
git -C "$P" checkout -q -- . ; rm -f "$P"/.backend-red "$P"/.backend-ran

H=block-dangerous-bash.sh
expect "C-4 no project rule without configuration" allow "$(decision $H "$(bash_json "$EVALS")")"

H=block-secret-reads.sh
expect "C-8 .env without configuration" deny "$(decision $H "$(read_json "$P/.env")")"
expect "C-8 no rule reference" no "$(mentions "$(reason $H "$(read_json "$P/.env")")" 'AGENTS')"

mkdir -p "$P/.claude"
printf '{"tests": ' > "$P/.claude/fastapi-harness.json"
expect "C-12 invalid configuration: defaults still apply" deny \
  "$(decision $H "$(read_json "$P/.env")")"
expect "C-12 invalid configuration: warns the person" yes \
  "$(mentions "$(warning $H "$(read_json "$P/.env")")" 'fastapi-harness\.json')"
expect "C-12 invalid configuration, allowed action: warns" yes \
  "$(mentions "$(warning $H "$(read_json "$P/app/service.py")")" 'fastapi-harness\.json')"
rm -rf "$P/.claude"

NOJQ=$(mktemp -d)
ln -s "$(command -v dirname)" "$NOJQ/dirname"
ln -s "$(command -v cat)" "$NOJQ/cat"
C13=$(bash_json 'git push --force' | env PATH="$NOJQ" "$BASH" "$HOOKS/block-dangerous-bash.sh" 2>/dev/null; echo "status=$?")
expect "C-13 without jq the hook lets the action through" "status=0" "$C13"
rm -rf "$NOJQ"

export CLAUDE_PROJECT_DIR="$SANDBOX"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "test_hooks: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
