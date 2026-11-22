---
description: Audita todo el backend contra el OWASP Top 10 web y el OWASP Top 10 para aplicaciones LLM, de a un hallazgo por vez y por orden de criticidad. Usar antes de cada entrega, no en cada pull request.
---

Actuá como auditor de seguridad de aplicaciones. Analizá el backend del proyecto contra dos
listas:

- el OWASP Top 10 de aplicaciones web, en su edición vigente;
- el OWASP Top 10 para aplicaciones LLM, en su edición vigente, si el proyecto usa un modelo de
  lenguaje.

Antes de empezar, confirmá cuál es la edición vigente de cada lista en el sitio de OWASP. No
uses la que recuerdes.

Leé `.claude/fastapi-harness.json` del proyecto para saber dónde están sus notas (`notes_dir`;
sin el archivo, `.claude/fastapi-harness/`). Si existe `<notes_dir>/security-audit.md`, leelo:
dice dónde está el backend y qué documentos y decisiones ya resuelven parte de las listas.
Leelos primero, para no reportar como hallazgo algo que el diseño resuelve en otro lado. Si no
hay notas, el backend es la carpeta que tiene la aplicación FastAPI, y lo ya decidido está en el
contrato del proyecto (`AGENTS.md` o `CLAUDE.md`) y en sus decisiones de arquitectura.

Después recorré el código y armá la lista completa de hallazgos, ordenada de mayor a menor
criticidad. Mostralos **de a uno**. Para cada hallazgo:

1. **Categoría** de OWASP a la que corresponde y **criticidad**: crítica, alta, media o baja.
2. **Código vulnerable:** el archivo, la línea y el fragmento.
3. **Riesgo:** qué puede hacer un atacante con eso en este proyecto, en concreto. Quién es, qué
   manda y qué obtiene.
4. **Corrección:** el cambio de código propuesto, respetando la arquitectura y las convenciones
   del contrato del proyecto.

Después de cada hallazgo, frená y esperá la respuesta antes de mostrar el siguiente.

Reglas de este comando, sin excepción:

- **No modifiques nada.** Mostrás la corrección; no la aplicás.
- Si un hallazgo contradice lo que dice la especificación, es una divergencia: reportala como
  tal, sin elegir un lado.
- Al citar un fragmento, no copies secretos ni datos personales: enmascaralos.
- Una categoría sin hallazgos se dice en una línea al final, con qué revisaste para afirmarlo.
- Si el proyecto todavía no tiene backend, decilo en una línea y terminá.
