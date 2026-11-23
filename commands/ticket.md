---
description: Recorre el flujo de trabajo de un corte, de la issue al pull request, con una pausa en cada punto que decide una persona. Usar al empezar un corte de una historia o una tarea, con el número de sus issues y el del corte.
argument-hint: <issues> c<corte>, por ejemplo 70 71 c2
---

Recorré el flujo de trabajo del proyecto para las issues y el corte que se te indican. Los
números son las issues, y el corte va con una `c` delante, como `c2`; una tarea no tiene cortes
y lleva solo sus issues.

## 0. Antes de empezar

- Leé `.claude/fastapi-harness.json` del proyecto. De ahí salen la rama integradora
  (`integration_branch`), dónde van las especificaciones (`specs`) y la carpeta de notas
  (`notes_dir`). Si el archivo no existe, la rama es `main`, las especificaciones van en
  `docs/features/<FEAT>/spec.md` y las notas en `.claude/fastapi-harness/`.
- Si existe `<notes_dir>/ticket.md`, leelo completo: son los pasos y los datos propios del
  proyecto. Cuando completan un paso de este comando, se suman a él; cuando lo contradicen,
  frená y preguntá.
- Leé el contrato del proyecto para asistentes, `AGENTS.md` o `CLAUDE.md`. Lo que manda es ese
  contrato: este comando lo ordena, no lo reemplaza.

Cada **pausa** es un punto en el que te detenés y esperás a la persona. No la saltes aunque el
paso siguiente parezca obvio, y no tomes un "dale" de una pausa como permiso para la siguiente.
Ningún commit ni push se hace sin que la persona lo pida, sea del tipo que sea, y ninguna
revisión se lanza sin que la pida: una verificación se corre cuando la persona decide.

Las dudas se preguntan de a una, con una escena concreta de uso y no con el nombre técnico, y
con una recomendación.

## 1. Arrancar

- Leé cada issue con `gh issue view`, la historia de usuario de la que sale y lo que el
  contrato del proyecto pide leer para ese tipo de cambio.
- Creá la rama desde la rama integradora, con el nombre que pide el proyecto, y pasá la
  tarjeta de cada issue a "En curso" si el proyecto usa un tablero.

## 2. Especificar

- En una historia, escribí o actualizá la `spec.md` de la funcionalidad desde la plantilla del
  proyecto (`specs.template_dir`).
- Si el proyecto no tiene esa carpeta, ofrecé copiar ahí las plantillas del plugin:
  `${CLAUDE_PLUGIN_ROOT}/templates/feature/spec.md`, `pr.md` y `ui_contract.md`. **Pausa:**
  copialas solo con el ok de la persona, leyendo cada archivo y escribiéndolo en la carpeta del
  proyecto. Desde ahí son del proyecto: no vuelvas a leer las del plugin, y decile que las
  ajuste donde marcan `<…>`.
- Si la especificación y el código no coinciden, o dos documentos de la especificación se
  contradicen, frená y reportalo: la decisión es de la persona.

## 3. Proponer los casos del corte

Proponé los casos del corte, cada uno con qué prueba, su tipo y de qué criterio sale. En una
tarea no hay `spec.md`: proponé cada caso en una línea, con su resultado esperado, o decí que no
hay lógica que probar. Los casos aprobados de una tarea van en la descripción del pull request.

**Pausa.** La persona los aprueba. En una historia, la línea de aprobación de `spec.md` la
escribe ella: no la completes vos. Un hook lo controla.

## 4. Escribir los tests y verlos fallar

Escribí los tests tal como se aprobaron, sin sumar ni cambiar casos, y corrélos. Mostrá cuáles
fallan y por qué, y cuáles ya pasan y por qué: un test que pasa antes de implementar se dice, no
se esconde.

**Pausa.** El commit `test(alcance): …`, solo si la persona lo pide.

## 5. Implementar

Implementá lo mínimo para que pasen y corré todos los controles que el contrato del proyecto
pide para lo que el cambio toca. Si un test parece mal, frená y mostralo: no se modifica sin
aprobación. La documentación que el cambio afecta entra en la misma rama. Si el corte cambió una
regla, un caso o un comportamiento, buscá con `grep` en la especificación, el contrato y el
`README.md` todo lo que lo menciona, y actualizalo también: una decisión se propaga en el mismo
pull request, no después.

**Pausa.** El commit `feat(alcance): …`, y los `docs(alcance): …` de la documentación, solo si
la persona los pide.

## 6. Cerrar el corte

**Pausa.** Preguntá si corrés `/fastapi-harness:spec-drift corte`, y
`/fastapi-harness:ui-states` si el cambio tiene pantalla. Lo que encuentren se resuelve con la
persona: se corrige en la rama, o queda en una issue que ella aprueba.

Si es el último corte de una historia, repasá con la persona lo que la historia resolvió o
desbloqueó en la hoja de ruta del proyecto, si tiene una.

## 7. Probar a mano

Dale los pasos exactos para verlo andar como lo usaría una persona: cómo se levanta, los datos
de prueba y qué mirar. Decí también qué no se puede probar a mano y qué test lo cubre.

**Pausa.** La persona prueba. Lo que surja se corrige en la misma rama. Si pide un test nuevo
o cambiar uno, es un caso nuevo: vuelve al paso 3, se propone, se aprueba y recién ahí se
escribe.

## 8. Revisar

**Pausa.** Preguntá si corrés el agente `fastapi-harness:pr-reviewer` sobre la rama. Resumí su
veredicto con los hallazgos por gravedad y resolvé con la persona qué se corrige ahora y qué
queda anotado. Una corrección que pide un test nuevo vuelve al paso 3, como en el paso 7.

## 9. Entregar

- **Pausa.** Subí la rama solo si la persona lo pide.
- Escribí la descripción del pull request desde la plantilla del proyecto, con el resumen de
  `pr-reviewer` en su sección de revisión. Un corte que no es el último lleva `Parte de #N`; el
  último, `Closes #N` de cada issue y también de la historia de usuario.
- **Pausa.** El merge lo hace la persona: vos nunca hacés merge. Si las notas del proyecto
  dicen quién abre el pull request, seguilas; si no, preguntá.
- Cuando se integra, confirmá que las issues que cerró quedaron cerradas.
