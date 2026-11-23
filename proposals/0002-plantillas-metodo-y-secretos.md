# 0002 — Las plantillas de una funcionalidad, el método escrito y los secretos

- **Estado:** aprobada x Veronica Zacarias el 23/11/2026, con las tres decisiones recomendadas.
- **Fecha:** 2026-11-23
- **Base:** `docs/features/TEMPLATE/`, `AGENTS.md` § 13, `docs/convenciones-de-desarrollo.md`
  y el `permissions.deny` de `.claude/settings.json` de `AI4Devs-finalproject` en `platita-v2`.

## Por qué

La propuesta 0001 llevó al plugin los hooks, los comandos y el agente, pero dejó en Platita
tres cosas de las que el plugin depende o que repite:

1. **La plantilla de la especificación.** El hook que protege la línea de aprobación y
   `/ticket` dan por hecho una `spec.md` con casos por corte y una línea `**Aprobado por:**`
   en cada uno. El plugin no trae esa plantilla: un proyecto nuevo tiene que adivinar el
   formato que el hook entiende.
2. **Lo que el plugin da por hecho.** `/ticket`, el agente y los hooks suponen reglas que el
   proyecto tiene que tener escritas: casos aprobados por una persona antes de los tests, una
   línea de aprobación en la especificación, tests en rojo antes de implementar. El README no
   las nombra: un proyecto nuevo no sabe qué escribir en su `AGENTS.md`.
3. **Los secretos, controlados dos veces.** `permissions.deny` de Platita y el hook
   `block-secret-reads.sh` cubren el mismo riesgo sin que esté dicho si es a propósito.

Esta propuesta reemplaza al borrador anterior de la 0002, que llevaba al plugin el verificador
de arquitectura. Se descartó: ese verificador controla la especificación de Platita (su ADR
0001), no el trabajo con el asistente, y moverlo haría que el pre-commit y el CI de Platita
dependieran del harness.

**Un criterio vale para las tres:** el proyecto no tiene que depender del plugin más de lo que
ya depende. Lo que el plugin trae es un punto de partida que el proyecto copia y hace suyo, no
algo que el proyecto tenga que leer del plugin para funcionar.

## Qué se propone

### 1. Las plantillas de una funcionalidad

```text
templates/feature/spec.md          criterios, casos por corte, línea de aprobación en cada uno
templates/feature/pr.md            la descripción del pull request
templates/feature/ui_contract.md   componentes, tokens, los cuatro estados, accesibilidad
```

Salen de las de Platita sin lo propio de Platita: WhatsApp, `reglas-de-dominio.md`, el grupo
familiar, la moneda, la aplicación móvil. Donde Platita enlaza un documento suyo, la plantilla
deja un lugar marcado para que el proyecto ponga el suyo.

La línea de aprobación se escribe con los valores por defecto de `specs.approval_marker` y
`specs.pending_value`, así que el hook la entiende sin configurar nada.

**Cómo llegan al proyecto:** `/ticket`, al escribir la `spec.md` de una historia, busca la
plantilla del proyecto en `specs.template_dir`. Si no existe, ofrece copiar la del plugin ahí y
espera el ok. Desde entonces la plantilla es del proyecto, que la cambia como quiera. El plugin
nunca la vuelve a leer.

El texto del comando nombra la carpeta del plugin con `${CLAUDE_PLUGIN_ROOT}`: Claude Code la
reemplaza por la ruta de la versión instalada al cargar el comando (comprobado el 23/11/2026 en
la referencia de plugins, sección «Environment variables»). La variable no existe en la terminal
del asistente, así que la copia se hace leyendo y escribiendo el archivo, no con un `cp`.

### 2. Lo que el plugin da por hecho

El método se escribe en un solo lugar como regla: el `AGENTS.md` (o `CLAUDE.md`) del proyecto.
El plugin no trae una copia del método. `/ticket` lo ejecuta paso a paso, y eso es la
herramienta cumpliendo la regla, no la regla.

El README suma una sección, «Lo que el proyecto tiene que tener escrito», con las reglas que el
plugin supone y que ningún hook hace cumplir del todo:

- los casos de un corte los aprueba una persona antes de que se escriba un test, y el
  asistente no completa la línea de aprobación;
- los tests se escriben tal como se aprobaron, se corren y se commitean en rojo antes de
  implementar;
- un test no se modifica, deshabilita ni borra para que la suite pase;
- el asistente hace commit solo cuando se lo piden, y nunca merge.

Cada una dice qué pieza del plugin la supone. Si la regla del proyecto y el plugin se
contradicen, manda la del proyecto, y se ajustan sus notas o el plugin.

### 3. Los secretos

Los dos controles se quedan, a propósito, y el README lo explica:

| | `permissions.deny` del proyecto | `block-secret-reads.sh` del plugin |
|---|---|---|
| Vale sin instalar el plugin | Sí | No: hasta el `plugin install` de cada clon, esa copia no tiene hooks |
| Cubre Grep y Glob | Sí: Claude Code aplica las reglas de `Read` a las herramientas que leen archivos | No: solo `Read` |
| Cubre `.env.local` y otras variantes | Solo si se escriben una por una, y una regla `.env.*` bloquearía también `.env.example` | Sí, y deja leer `.env.example` |
| Explica el rechazo | No | Sí, y dice qué leer en su lugar |

Cambia esto en el plugin:

- **El hook también mira `Grep`** cuando su `path` es un archivo de secretos. Hoy alcanza con
  pedir un Grep sobre `.env` para ver su contenido sin pasar por el hook.
- **`templates/settings-deny.json`:** el bloque de `permissions.deny` recomendado, para que el
  proyecto lo copie a su `settings.json`. Es el de Platita.
- **El README** dice por qué van los dos.

## Los casos

`tests/test_plugin.sh`:

| Caso | Entrada | Esperado |
|---|---|---|
| P-9 | `templates/feature/spec.md` | existe, y tiene tres líneas de aprobación con `**Aprobado por:**` y `pendiente` |
| P-10 | Una copia de `templates/feature/spec.md` en el `specs.template_dir` de un proyecto de prueba, y completar ahí su línea de aprobación | el hook deja pasar: es la plantilla, no una especificación |
| P-11 | La misma copia en `docs/features/FEAT-1/spec.md`, y completar su línea de aprobación | el hook rechaza |
| P-12 | `templates/feature/pr.md` y `templates/feature/ui_contract.md` | existen, y `ui_contract.md` tiene los cuatro estados |
| P-13 | El README | tiene la sección «Lo que el proyecto tiene que tener escrito», y no existe `metodo.md` ni otra copia del método en el plugin |
| P-14 | `templates/settings-deny.json` | es un JSON válido con `permissions.deny`, y no deja afuera ningún nombre que el hook rechaza (`.env`, `credentials*`, `id_rsa`, `id_ed25519`, `*.pem`, `*.key`, `service-account*.json`) |
| P-15 | `commands/ticket.md` | nombra `specs.template_dir` y la copia de la plantilla del plugin con el ok de la persona |

P-7, que comprueba que nada del plugin nombre a Platita ni a una persona, pasa a cubrir también
`templates/`.

`tests/test_hooks.sh`:

| Caso | Entrada | Esperado |
|---|---|---|
| S-1 | Grep con `path` = `.env` | deny |
| S-2 | Grep con `path` = `config/.env.local` | deny |
| S-3 | Grep con `path` = `.env.example` | allow |
| S-4 | Grep con `path` = `app/` | allow |
| S-5 | Grep sin `path` | allow |
| S-6 | Grep con `path` = `frontend/e2e/compose.env` y ese archivo en `secrets_allowed` | allow |

`hooks/hooks.json` registra el hook con el matcher `Read|Grep`, y P-3 lo comprueba.

## Lo que cambia en Platita

Casi nada, y es a propósito.

- **Las plantillas:** Platita conserva las suyas en `docs/features/TEMPLATE/`. Son más
  completas que las del plugin y son de Platita. Como `specs.template_dir` ya apunta ahí,
  `/ticket` nunca ofrece copiar las del plugin.
- **El método:** `AGENTS.md` § 13 y `convenciones-de-desarrollo.md` se quedan como están, sin
  enlazar al plugin. Son el contrato de Platita y tienen que valer con cualquier harness.
- **Los secretos:** `permissions.deny` se queda. El hook pasa a cubrir Grep sin que Platita
  toque nada.
- **La versión:** `.claude/settings.json` cambia `ref` a `v0.2.0`, en una rama
  `tarea-harness-v0-2-0` desde `platita-v2`, por pull request. Si la especificación de Platita
  nombra la versión fijada (como los enlaces a `blob/v0.1.1/` de `documentacion-viva.md`,
  `flujo-de-trabajo-con-ia.md` y `seguridad-llm.md`), se actualizan en la misma rama.

Lo que queda pendiente en Platita, aparte de esta propuesta: bajar su acoplamiento con el
plugin en la documentación. Que el plugin se nombre solo en el ADR 0032 y en un apartado de
`flujo-de-trabajo-con-ia.md`, y que el resto hable del rol («el agente revisor») sin prefijo ni
versión. Es una tarea de Platita, no de este repo.

## El orden

1. Aprobar esta propuesta, los casos y las decisiones.
2. Comprobar si el texto de un comando puede usar `${CLAUDE_PLUGIN_ROOT}`.
3. En este repo: los tests con los casos, commit en rojo, el hook, las plantillas y el comando
   hasta el verde, y el README.
4. Push y el tag `v0.2.0`, con el OK de quien desarrolla.
5. En Platita: la rama con el `ref` nuevo, `pr-reviewer` y el pull request. El merge lo hace
   quien desarrolla.

## Decisiones para aprobar

1. **Las plantillas se copian una vez y pasan a ser del proyecto**, en lugar de que el plugin
   las lea en cada uso. **Elegida el 23/11/2026.** Un proyecto ajusta su especificación sin pedirle nada al
   plugin, y puede cambiar de harness sin perderla.
2. **El método vive solo en el proyecto.** El plugin no trae una copia: su README dice qué
   reglas supone, y el `AGENTS.md` del proyecto no describe el plugin. **Elegida el
   23/11/2026.**
3. **Los dos controles de secretos se quedan, a propósito.** **Elegida el 23/11/2026.** `permissions.deny`
   cubre la copia sin el plugin instalado y las otras herramientas de lectura, y el hook cubre
   las variantes y explica el rechazo.
