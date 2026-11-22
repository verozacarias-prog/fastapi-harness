---
description: Verifica que una pantalla del dashboard implementa y testea los cuatro estados obligatorios. Usar antes de cerrar el corte vertical 2 de cualquier funcionalidad con interfaz.
---

Revisá la pantalla indicada contra la regla de los cuatro estados del proyecto.

Leé `.claude/fastapi-harness.json` del proyecto para saber dónde están sus notas (`notes_dir`;
sin el archivo, `.claude/fastapi-harness/`). Si existe `<notes_dir>/ui-states.md`, leelo: dice
dónde está la regla, qué pantallas son una excepción y el caso típico de estado vacío del
proyecto.

Para cada uno de los cuatro —cargando, con contenido, vacío y error— reportá:

- Si está **implementado** en el código, con el archivo y la línea donde se resuelve.
- Si está **testeado**, con el test que lo cubre.
- Qué se le muestra al usuario.

Prestá atención especial a esto, que es donde se falla: **vacío y error no son el mismo estado.**
Una consulta que funcionó y no devolvió datos está vacía, no falló. Mostrarle un error al
usuario en ese caso sería mentirle.

Si encontrás que el estado vacío está resuelto como error, como pantalla en blanco o como un
spinner infinito, marcalo como error del corte, no como mejora pendiente.

Terminá con un veredicto de una línea: si los cuatro estados están completos y testeados, el
corte 2 puede cerrarse; si no, listá exactamente qué falta.
