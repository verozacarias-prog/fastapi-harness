# 0001 — Extraer el harness de Platita a un plugin para proyectos FastAPI

- **Estado:** aprobada el 21/11/2026, con las tres decisiones recomendadas y sin el aviso de
  plugin sin instalar.
- **Fecha:** 2026-11-21
- **Base:** los hooks, el agente y los comandos de `AI4Devs-finalproject` en `platita-v2`
  (PR #226, ADR 0031 y ADR 0022 de ese repo).

## Por qué

El harness de Platita vive dentro de Platita: cambiar un hook pide una rama del proyecto, el
pull request con `pr-reviewer`, los tres verificadores y el portal. Mejorar el proceso frena al
producto, y lo que se aprendió no se puede usar en otro proyecto.

Lo mismo se resolvió en Apex con `apex-harness`. Acá cambia una cosa: los repos de Apex no se
tocan, y por eso ese harness se instala con enlaces en `~/.claude`. Platita sí versiona su
harness, y lo tienen que encontrar igual cualquier clon y el CI. Por eso esta vez se arma un
**plugin de Claude Code**, y el repo es también su propio marketplace.

## Qué se propone

### El repo

`<owner>/fastapi-harness`, público, con esta forma:

```text
.claude-plugin/plugin.json        nombre, versión, descripción
.claude-plugin/marketplace.json   un solo plugin, con "source": "./"
hooks/hooks.json                  registro de los hooks, con ${CLAUDE_PLUGIN_ROOT}
hooks/*.sh                        los cuatro hooks y lib.sh
commands/                         ticket, spec-drift, security-audit, ui-states
agents/pr-reviewer.md
config/default.json               valores por defecto para un FastAPI estándar
tests/test_hooks.sh               los casos de hoy, más los de la configuración
.github/workflows/hooks.yml       corre los tests en cada push y pull request
propuestas/                       el registro de los cambios grandes
README.md
```

Lo que **no** entra en esta etapa:

- los verificadores (`verify_architecture.py`, `verify_docs.py` y `verify_api_contract.py`):
  siguen en Platita. Una versión hexagonal configurable de `verify_architecture.py` queda como
  propuesta 0002;
- la skill `domain-rules`: es del dominio de Platita.

### La configuración de cada proyecto

Cada proyecto escribe en `.claude/fastapi-harness.json` solo lo que difiere de
`config/default.json`. Los hooks combinan los dos con `jq`. Sin ese archivo, valen los valores
por defecto, pensados para un proyecto con `app/`, `tests/`, `alembic/versions/` o `migrations/versions/`, y `.venv/`.

Así quedaría el de Platita:

```json
{
  "integration_branch": "platita-v2",
  "secrets_allowed": [".env.example", "frontend/e2e/compose.env"],
  "tests": {
    "dirs": ["backend/tests/", "frontend/e2e/"],
    "file_pattern": "\\.test\\.tsx?$"
  },
  "specs": {
    "glob": "docs/features/*/spec.md",
    "template_dir": "docs/features/TEMPLATE/",
    "approval_marker": "**Aprobado por:**",
    "pending_value": "pendiente"
  },
  "migrations_dirs": ["backend/migrations/versions/"],
  "suites": [
    {
      "name": "Backend",
      "watch": ["backend/app", "backend/tests"],
      "tests_pattern": "^backend/tests/",
      "cwd": "backend",
      "runner": ".venv/bin/python",
      "args": ["-m", "pytest", "-m", "not integration", "-q"],
      "missing_hint": "falta backend/.venv"
    },
    {
      "name": "Dashboard",
      "watch": ["frontend/src"],
      "tests_pattern": "\\.test\\.tsx?$",
      "cwd": "frontend",
      "runner": "node_modules/.bin/vitest",
      "args": ["run"],
      "missing_hint": "falta frontend/node_modules (npm ci)"
    }
  ],
  "bash_rules": {
    "deny": [
      {
        "pattern": "render[[:space:]]+deploys?([[:space:]]|$)",
        "message": "Ningún asistente despliega: lo aprueba y lo hace una persona."
      }
    ],
    "ask": [
      {
        "pattern": "evals\\.classification\\.run.*[[:space:]]--run([[:space:]]|$)",
        "message": "El set de regresión con --run llama al modelo real y cuesta plata. Corré primero sin --run y decí cuántas llamadas son."
      }
    ]
  },
  "dependency_hint": "En el backend se agrega al .in y se corre scripts/lock_backend_dependencies.sh.",
  "rule_refs": {
    "secrets": "AGENTS.md § 7",
    "tests": "AGENTS.md § 13 y ADR 0024",
    "approval": "AGENTS.md § 13",
    "migrations": "AGENTS.md § 8",
    "commit": "AGENTS.md § 13",
    "dependencies": "AGENTS.md § 9"
  },
  "notes_dir": ".claude/fastapi-harness/"
}
```

- **`rule_refs`:** cada mensaje de un hook termina con la referencia del proyecto, si la hay.
  Los textos del plugin no nombran `AGENTS.md` ni números de ADR.
- **`bash_rules`:** las reglas que solo tienen sentido en un proyecto, como las evals o el
  deploy a Render, viven en su configuración y no en el plugin. Se aplican después de las del
  plugin, con el mismo orden: primero las que rechazan y después las que preguntan.

### Los hooks

Siguen siendo los mismos cuatro, con la misma lógica. Cambia solo de dónde sale cada valor:

| Hook | Lo que deja de estar escrito en el código |
|---|---|
| `block-secret-reads.sh` | La excepción de `frontend/e2e/compose.env` pasa a `secrets_allowed` |
| `protect-tests-and-specs.sh` | Las carpetas de tests, la spec y su línea de aprobación, y las migraciones. La pregunta antes de editar los hooks pasa a cubrir `.claude/settings*.json` y `.claude/fastapi-harness.json` del proyecto |
| `verify-tests-on-stop.sh` | Las dos suites, que pasan a `suites`, en la cantidad que tenga el proyecto. La salida de emergencia pasa a llamarse `HARNESS_ALLOW_RED=1` |
| `block-dangerous-bash.sh` | Las evals, Render y el lockfile del backend pasan a `bash_rules` y a `dependency_hint`. Producción (`ENV=production`) queda en el plugin: vale para cualquier proyecto |

### Los comandos y el agente

Pasan con su método y sin lo propio de Platita. La rama integradora sale de
`integration_branch`, y los documentos que leen salen del `AGENTS.md` del proyecto. Lo que hoy
es solo de Platita va a un archivo de notas del proyecto:

- en `/ticket`: la skill `domain-rules`, `../pr-platita/<rama>.md`, `cd site && npm run build`
  y `unset GITHUB_TOKEN`;
- en `pr-reviewer`: las siete invariantes y `docs/seguridad-llm.md`;
- en `/security-audit`: los ADR que tiene que leer antes;
- en `/ui-states`: el ejemplo del presupuesto sin movimientos.

Cada comando y el agente leen primero `<notes_dir>/<nombre>.md`, si existe, como pasos del
proyecto que se suman a los suyos. En Platita esos archivos quedan en
`.claude/fastapi-harness/`, versionados con el proyecto.

Con el plugin, los nombres llevan prefijo: `/fastapi-harness:ticket` y el agente
`fastapi-harness:pr-reviewer`.

### Cómo se usa en un proyecto

En `.claude/settings.json` del proyecto:

```json
{
  "extraKnownMarketplaces": {
    "fastapi-harness": {
      "source": { "source": "github", "repo": "<owner>/fastapi-harness", "ref": "v0.1.0" }
    }
  },
  "enabledPlugins": { "fastapi-harness@fastapi-harness": true }
}
```

Y una vez por clon: `claude plugin install fastapi-harness@fastapi-harness --scope project`.

- **Una versión nueva** es un tag del repo. El proyecto la toma cambiando `ref` en su
  `settings.json` y corriendo `claude plugin update fastapi-harness@fastapi-harness`.
- **Mientras se desarrolla el harness,** `claude plugin marketplace add ~/MisProyectos/fastapi-harness`
  lo carga desde la carpeta local. Un cambio vale desde la sesión siguiente o con
  `/reload-plugins`, sin tag ni push.

### Lo que se pierde, y cómo se compensa

- **Hoy los hooks valen apenas se clona Platita.** Con el plugin, valen después del
  `claude plugin install` de cada clon. El README de Platita y `como-colaborar.md` lo ponen
  como primer paso.
- **El CI de Platita deja de correr los tests de los hooks.** Pasan al CI de este repo, que es
  donde cambian. Platita fija una versión con `ref`, así que un hook roto no le llega hasta
  que cambia el tag.

## Los casos

Las 109 comprobaciones de `scripts/test_assistant_hooks.sh` pasan tal cual a `tests/test_hooks.sh`. El
sandbox lleva la configuración de Platita de arriba, así que su resultado no cambia. Se suman
estos casos:

| Caso | Entrada | Esperado |
|---|---|---|
| C-1 | Sin `.claude/fastapi-harness.json`, editar una aserción de `tests/test_x.py` | ask |
| C-2 | Sin configuración, editar `alembic/versions/0001_init.py` ya versionado | ask |
| C-3 | Sin configuración, Stop con un cambio en `app/` y `.venv/bin/python` en rojo | block |
| C-4 | Sin configuración, `python -m evals.classification.run --run` | allow |
| C-5 | Con `bash_rules.ask` de Platita, el mismo comando | ask, con el mensaje configurado |
| C-6 | Con `bash_rules.deny` de Platita, `render deploys create` | deny |
| C-7 | Con `rule_refs.secrets` = `AGENTS.md § 7`, leer `.env` | deny, con «AGENTS.md § 7» en el mensaje |
| C-8 | Sin `rule_refs`, leer `.env` | deny, sin referencia |
| C-9 | Una tercera suite configurada, con un cambio solo en su `watch` y en rojo | block, y las otras dos no corren |
| C-10 | `HARNESS_ALLOW_RED=1` con la suite en rojo | allow, y no corre ninguna suite |
| C-11 | Editar `.claude/fastapi-harness.json` del proyecto | ask |
| C-12 | `.claude/fastapi-harness.json` con JSON inválido | ningún hook rompe la sesión: valen los valores por defecto y el hook avisa por `systemMessage` |
| C-13 | Sin `jq` en el `PATH` | los hooks dejan pasar, igual que hoy |

`tests/test_plugin.sh` comprueba además que `claude plugin validate .` pase, que cada comando y
el agente tengan su frontmatter completo, y que ningún archivo del plugin nombre a Platita, sus
rutas o datos de una persona.

## Lo que cambia en Platita

Va en una rama `tarea-harness-externo` desde `platita-v2`, por pull request, **después** de
publicar `v0.1.0` de este repo. Toca la especificación, así que cada punto es una divergencia
que decide quien desarrolla:

| Dónde | Hoy dice | Pasaría a decir |
|---|---|---|
| ADR 0031 | Los hooks viven en `.claude/hooks/` y se prueban con `scripts/test_assistant_hooks.sh` | `Reemplazada por 0032`. El ADR 0032 decide el plugin, la versión fijada y la configuración |
| ADR 0022 | `pr-reviewer` es «un agente definido en el repositorio» | Lo corrige el 0032, o un párrafo en el 0022 mientras no tenga «En producción desde» |
| `AGENTS.md` § 11 | Los cuatro hooks en `.claude/hooks/`, probados con el script del repo | Los hooks del plugin `fastapi-harness`, en la versión que fija `settings.json` |
| `docs/flujo-de-trabajo-con-ia.md` | Comandos en `.claude/commands/`, agente en `.claude/agents/`, hooks en `.claude/hooks/` y `PLATITA_PERMITIR_ROJO` | El plugin, sus nombres con prefijo y `HARNESS_ALLOW_RED` |
| `docs/documentacion-viva.md`, `docs/seguridad-llm.md` | Enlazan `.claude/commands/spec-drift.md` y `security-audit.md` | Enlazan el comando del plugin |
| `docs/08-convenciones-de-documentacion.md` y `scripts/verify_docs.py` | Validan el frontmatter de `.claude/commands/` y `.claude/agents/` | Validan solo `.claude/skills/`. Lo demás lo valida `tests/test_plugin.sh` en el plugin |
| `.github/workflows/app-quality.yml` | Corre `scripts/test_assistant_hooks.sh` | Ya no lo corre |

Lo que se borra de Platita: `.claude/hooks/`, `.claude/commands/`, `.claude/agents/`,
`scripts/test_assistant_hooks.sh` y el bloque `hooks` de `.claude/settings.json`. Lo que se
suma: `.claude/fastapi-harness.json` y las notas de `.claude/fastapi-harness/`. Quedan
`.claude/skills/domain-rules/` y el `permissions.deny`.

`docs/use-case-walkthrough.md` es un registro: no se toca.

## El orden

1. Aprobar esta propuesta y los casos.
2. En este repo: los tests con los casos, commit en rojo, los hooks parametrizados hasta el
   verde, los comandos y el agente, y el README.
3. Crear el repo en GitHub, push, y el tag `v0.1.0`, todo con el OK de quien desarrolla.
4. En Platita: la rama `tarea-harness-externo` con lo de la tabla de arriba, `pr-reviewer`
   (ya desde el plugin) y el pull request. El merge lo hace quien desarrolla.

## Decisiones para aprobar

1. **El nombre de la salida de emergencia:** `HARNESS_ALLOW_RED` en lugar de
   `PLATITA_PERMITIR_ROJO`. Recomendado, porque el plugin no conoce a Platita.
2. **El idioma:** el código y los comentarios en inglés, y los mensajes de los hooks, los
   comandos, el agente y la documentación en español, como en Platita y en `apex-harness`.
3. **El ADR 0032 en Platita** para reemplazar al 0031, en lugar de corregir el 0031 en su
   archivo. Recomendado: cambia dónde vive el control, no un detalle.
