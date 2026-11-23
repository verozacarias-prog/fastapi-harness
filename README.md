# fastapi-harness

El harness de Claude Code para proyectos Python y FastAPI que trabajan con tests primero y con
la especificación en `docs/`. Es un plugin: hooks que controlan con código las reglas que no
pueden depender de la memoria del modelo, comandos para el flujo de un corte y un agente que
revisa los pull requests.

El repo es también su propio marketplace: no hay que pagar ni publicar nada en otro lado.

## Qué trae

### Los hooks

Claude Code los corre solo, antes de cada acción o al cerrar un turno.

| Hook | Cuándo | Qué hace |
|---|---|---|
| `block-secret-reads.sh` | Antes de leer o de buscar con Grep | Rechaza `.env` y sus variantes, claves (`*.pem`, `*.key`, `id_rsa`), credenciales y `service-account*.json`. Deja leer `.env.example` y lo que el proyecto declare en `secrets_allowed`. En un Grep mira solo la ruta que se le pasa: una búsqueda sobre una carpeta queda, en lo posible, para el `permissions.deny` del proyecto ([abajo](#los-secretos-dos-controles-a-propósito)) |
| `protect-tests-and-specs.sh` | Antes de editar o escribir | Rechaza editar archivos de entorno y completar la línea de aprobación de una `spec.md`. Pregunta antes de cambiar, borrar o deshabilitar algo de un test existente, editar una migración ya versionada o tocar los hooks y su configuración |
| `block-dangerous-bash.sh` | Antes de un comando | Rechaza el borrado recursivo, leer secretos por la terminal, el push forzado, reescribir la historia, `--no-verify`, el merge y operar contra `production`. Pregunta antes de borrar o reescribir un test, descartar trabajo local, hacer commit o push, e instalar una dependencia. Suma las reglas propias del proyecto |
| `verify-tests-on-stop.sh` | Al cerrar el turno | Corre las suites que tienen cambios sin commitear y no deja cerrar el turno con una en rojo. Si lo único que cambió son tests, es la fase en rojo y deja pasar |

Para explorar en local con la suite en rojo, `HARNESS_ALLOW_RED=1` en el `env` de
`.claude/settings.local.json` apaga el último. Nunca dentro de una entrega.

### Los comandos y el agente

| Pieza | Cuándo |
|---|---|
| `/fastapi-harness:ticket <issues> c<corte>` | Al empezar un corte: de la issue al pull request, con una pausa en cada punto que decide una persona |
| `/fastapi-harness:spec-drift corte\|proyecto` | Al cerrar un corte y antes de una entrega: la especificación contra el código, sin resolver nada |
| `/fastapi-harness:security-audit` | Antes de una entrega: OWASP Top 10 web y para aplicaciones LLM, de a un hallazgo |
| `/fastapi-harness:ui-states` | Antes de cerrar un corte con pantalla: los cuatro estados, implementados y testeados |
| Agente `fastapi-harness:pr-reviewer` | Antes de pedir el merge, en un contexto separado del de quien escribió el cambio |

## Cómo se usa en un proyecto

1. En `.claude/settings.json` del proyecto, versionado:

   ```json
   {
     "extraKnownMarketplaces": {
       "fastapi-harness": {
         "source": { "source": "github", "repo": "<owner>/fastapi-harness", "ref": "v0.2.1" }
       }
     },
     "enabledPlugins": { "fastapi-harness@fastapi-harness": true }
   }
   ```

2. Una vez por clon, para que los hooks valgan en esa copia:

   ```sh
   claude plugin install fastapi-harness@fastapi-harness --scope project
   ```

   Hasta que se corre, esa copia trabaja sin hooks. Ponelo como primer paso en el README del
   proyecto.

3. El bloque `permissions.deny` de [`templates/settings-deny.json`](templates/settings-deny.json)
   en el mismo `settings.json` ([abajo](#los-secretos-dos-controles-a-propósito)).

4. Las reglas que el plugin supone, escritas en el `AGENTS.md` o `CLAUDE.md` del proyecto
   ([abajo](#lo-que-el-proyecto-tiene-que-tener-escrito)).

5. Si el proyecto no tiene la forma por defecto, su `.claude/fastapi-harness.json` (abajo).

6. Si un comando necesita pasos propios del proyecto, sus notas en `.claude/fastapi-harness/`
   (abajo).

## Lo que el proyecto tiene que tener escrito

El plugin no trae el método de trabajo: lo ejecuta. El método es una regla del proyecto y se
escribe una sola vez, en su `AGENTS.md` o `CLAUDE.md`, con sus palabras. Ese archivo no tiene
que describir el plugin: los hooks corren solos, y los comandos y el agente aparecen con su
descripción.

Lo que sí tiene que estar escrito son las reglas que el plugin supone y que ningún hook hace
cumplir del todo. Sin ellas, el asistente se entera recién cuando un hook lo frena, o no se
entera:

| Regla | Qué pieza la supone |
|---|---|
| Los casos de un corte los aprueba una persona antes de que se escriba un test, y el asistente no completa la línea de aprobación | `/ticket` (pasos 3 y 4) y `protect-tests-and-specs.sh`, que solo controla la línea |
| Los tests se escriben tal como se aprobaron, se corren y se commitean en rojo antes de implementar | `/ticket` (paso 4) y `verify-tests-on-stop.sh`, que deja cerrar el turno en rojo solo si lo único que cambió son tests |
| Un test no se modifica, deshabilita ni borra para que la suite pase | `protect-tests-and-specs.sh` y `block-dangerous-bash.sh`, que preguntan pero no deciden |
| El asistente hace commit solo cuando se lo piden, y nunca merge | `/ticket`, `block-dangerous-bash.sh` (pregunta el commit, rechaza el merge) |

Si una regla del proyecto y el plugin se contradicen, manda la del proyecto: se ajustan sus
notas o se propone el cambio acá.

## Las plantillas de una funcionalidad

[`templates/feature/`](templates/feature/) trae `spec.md`, `pr.md` y `ui_contract.md`: los
criterios, los casos por corte con su línea de aprobación, la descripción del pull request y
el contrato de una pantalla. La línea de aprobación usa los valores por defecto de `specs`, así
que el hook la entiende sin configurar nada.

Se copian una vez. Si el proyecto no tiene la carpeta de `specs.template_dir`, `/ticket` ofrece
copiarlas ahí y espera el ok. Desde entonces son del proyecto, que las ajusta donde marcan
`<…>`, y el plugin no las vuelve a leer.

## Los secretos: dos controles, a propósito

| | `permissions.deny` del proyecto | `block-secret-reads.sh` |
|---|---|---|
| Vale sin instalar el plugin | Sí | No: hasta el `plugin install` de cada clon, esa copia no tiene hooks |
| Cubre las otras herramientas que leen archivos, como un Grep sobre una carpeta | En lo posible: Claude Code dice que aplica las reglas de `Read` a Grep y Glob «best-effort», sin garantizarlo | No: `Read`, y `Grep` sobre la ruta exacta |
| Cubre `.env.local` y otras variantes | Solo si se escriben una por una: `.env.*` bloquearía también `.env.example` | Sí, y deja leer `.env.example` |
| Cubre archivos como `compose.env` (`*.env`) | No: el bloque sugerido no los nombra | Sí, salvo los que el proyecto declare en `secrets_allowed` |
| Explica el rechazo | No | Sí, y dice qué leer en su lugar |

Por eso van los dos: el `deny` del proyecto es la red que no depende del plugin, y el hook
cubre lo que el `deny` no puede expresar.

## La configuración

El plugin trae [`config/default.json`](config/default.json), pensado para un servicio con
`app/`, `tests/`, `alembic/versions/` o `migrations/versions/`, y `.venv/`. Un proyecto escribe
en `.claude/fastapi-harness.json` solo lo que difiere: los dos se combinan, y una lista del
proyecto reemplaza a la del plugin. Si el archivo no es un JSON válido, los hooks usan los
valores por defecto y lo avisan.

| Clave | Qué es |
|---|---|
| `integration_branch` | La rama de la que salen las ramas de trabajo. La usan los comandos y el agente |
| `secrets_allowed` | Archivos que parecen de secretos y se pueden leer. Con barra, una ruta exacta; sin barra, un nombre en cualquier carpeta |
| `tests.dirs` | Las carpetas de tests |
| `tests.file_pattern` | Una expresión regular para los tests que viven fuera de esas carpetas, como `\\.test\\.tsx?`. Sin anclas: se le agrega el final de la ruta |
| `specs` | Dónde van las especificaciones (`glob`), su plantilla, el texto de la línea de aprobación y el valor que queda mientras está pendiente |
| `migrations_dirs` | Las carpetas de migraciones |
| `suites` | Las suites del hook de cierre: qué rutas mira (`watch`), qué archivos son tests (`tests_pattern`), desde qué carpeta corre (`cwd`), el ejecutable (`runner`), sus argumentos y qué decir si falta |
| `bash_rules` | Las reglas propias del proyecto, en `deny` y en `ask`, cada una con su `pattern` (expresión regular extendida) y su `message` |
| `dependency_hint` | Lo que se suma al aviso de una dependencia nueva, como el script de lockfile del proyecto |
| `rule_refs` | Dónde escribe el proyecto cada regla (`secrets`, `tests`, `approval`, `migrations`, `commit`, `verify`, `dependencies`), para citarlo en el mensaje del hook. `verify` es la de los controles que corren antes de un commit, y la cita el rechazo de `--no-verify`; sin ella, ese rechazo cita `commit` |
| `notes_dir` | La carpeta de las notas del proyecto para los comandos y el agente |

Un ejemplo completo, con un backend y un dashboard, está en
[`tests/fixtures/project-config.json`](tests/fixtures/project-config.json).

### Las notas del proyecto

Los comandos y el agente traen el método; lo que es de un solo proyecto va en sus notas. Cada
uno lee `<notes_dir>/<nombre>.md` si existe: `ticket.md`, `spec-drift.md`,
`security-audit.md`, `ui-states.md` y `pr-reviewer.md`. Por ejemplo, la skill de dominio que hay
que usar, dónde se guarda la descripción de un pull request o qué invariantes mirar al revisar.

## Cómo se cambia el harness

- **Mientras desarrollás,** cargalo desde tu copia local, así un cambio vale sin tag ni push:

  ```sh
  claude plugin marketplace add ~/ruta/a/fastapi-harness
  ```

  Vale desde la sesión siguiente, o con `/reload-plugins`.

- **Un hook se escribe con tests primero:** los casos se proponen y se aprueban, se escriben en
  `tests/` y se commitean en rojo, y recién después se implementa.
- **Un cambio grande** empieza como propuesta en `proposals/NNNN-<tema>.md`.
- **Una versión nueva** sube `version` en `.claude-plugin/plugin.json` y lleva su tag. Cada
  proyecto la toma cambiando `ref` en su `settings.json` y corriendo
  `claude plugin update fastapi-harness@fastapi-harness`.
- **La estructura va en inglés y el contenido para personas, en español:**
  - en inglés: las carpetas, los nombres de los archivos de código y de configuración, las
    claves de la configuración, los nombres de los comandos y del agente, el código, los
    comentarios y los nombres de los casos de test;
  - en español: los nombres de los documentos (como `proposals/0002-plantillas-metodo-y-secretos.md`),
    el README, las propuestas, el texto de los comandos y del agente, los mensajes de los hooks
    y los commits.

  Varios nombres en inglés los exige Claude Code: `.claude-plugin/`, `commands/`, `agents/` y
  `hooks/hooks.json`.
- Sin nombres de proyectos ni de personas fuera de `proposals/`, que es el registro. La
  autora figura solo donde se declara la autoría: `LICENSE` y el `author` de `plugin.json`.

## Los tests

```sh
bash tests/test_hooks.sh    # cada hook, contra proyectos de prueba descartables
bash tests/test_plugin.sh   # manifiestos, registro de hooks, configuración, frontmatter y plantillas
```

Necesitan `bash`, `git` y `jq`. El CI los corre en cada push y en cada pull request.

## Origen

Los hooks se adaptaron del SDD Harness Kit (`github.com/DisTinta/sdd-harness-kit`, licencia
MIT).
