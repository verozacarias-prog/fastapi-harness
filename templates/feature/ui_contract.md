# Contrato de UI — <ID> · <pantalla>

- **Historia de usuario:** <enlace a la historia>
- **Especificación:** [spec.md](spec.md)
- **Se escribe:** antes del corte 1, junto con la especificación

Este documento vive separado de los componentes a propósito: los tokens y la máquina de estados
son el contrato de la pantalla, no de la tecnología que la dibuja. Si vivieran dentro de los
componentes, habría que reconstruirlos leyendo código.

## Componentes

Qué se usa y qué se crea. Si se crea uno nuevo, decir por qué no alcanzaba uno existente.

| Componente | ¿Existe o es nuevo? | Para qué |
|---|---|---|

## Tokens de diseño

Solo tokens, nunca valores sueltos.

| Uso | Token |
|---|---|

## Máquina de estados

Los cuatro estados son obligatorios. Vacío y error no son el mismo estado: una consulta que
funcionó y no devolvió datos está vacía, no falló.

| Estado | Qué lo dispara | Qué muestra | Cómo se sale |
|---|---|---|---|
| Cargando | | | |
| Con contenido | | | |
| Vacío | | | |
| Error | | | |

## Datos que consume

Qué endpoint alimenta la pantalla, y qué campos usa.

## Accesibilidad

- [ ] Todo control tiene nombre accesible.
- [ ] El contraste cumple el mínimo de la guía de diseño.
- [ ] La pantalla se puede operar solo con teclado.
- [ ] Los números se anuncian con su unidad, no como número suelto.

## Textos

Ningún texto visible se escribe en el componente. Listar acá las claves y su contenido.
