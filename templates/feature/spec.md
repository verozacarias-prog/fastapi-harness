# Especificación — <ID> · <título>

- **Historia de usuario:** <enlace a la historia>
- **Estado:** borrador | aprobada
- **Fecha:** AAAA-MM-DD

## Alcance

Qué entra y qué no. Si algo se deja afuera, decir por qué: decisión de alcance, no omisión.

## Reglas que aplican

Las reglas de negocio del proyecto que rigen esta funcionalidad. No copiar su texto: enlazar
el documento donde están escritas.

- <regla y enlace>

## Criterios de aceptación

Cada criterio es una regla, en una frase, dicha desde lo que hace o ve la persona. Vale para
cualquier dato. Van agrupados por requisito, y cada uno lleva un identificador, `CA-1`,
`CA-2`…, que no se reutiliza ni se renumera: los casos y los tests lo citan.

### <Requisito>

<La regla general, en una frase.>

- **CA-1.** <El criterio.>

## Casos de prueba

Cada caso es un ejemplo concreto de un criterio, con datos que se pueden revisar a mano, y se
entiende solo, sin leer los demás. Se escriben antes de cada corte y los aprueba una persona:
hasta entonces no se escribe ningún test. La línea "Aprobado por" la completa esa persona,
nunca un asistente: mientras tanto dice `pendiente`.

### Corte 1 — camino feliz

- **Aprobado por:** pendiente
- **Total:** N casos, N unitarios y N de integración.

| Caso | Qué prueba | Tipo | Sale de |
|---|---|---|---|
| C1-01 | | Unitario | CA-1 |

#### C1-01 · <qué prueba el caso>

- **Sale de:** CA-1 · **Tipo:** unitario | integración | componente
- **Dado** <el estado inicial completo>,
- **cuando** <una sola acción>,
- **entonces** <el estado final, con la cuenta escrita si hay un cálculo>.
- **Test:** — <el archivo y el nombre del test, cuando existe>

### Corte 2 — errores y estado vacío

- **Aprobado por:** pendiente

Qué pasa cuando falla una consulta o un servicio externo no responde, y los casos límite de la
funcionalidad: valores en cero, listas vacías, datos que faltan.

Siempre, si la funcionalidad lee o escribe datos de un usuario: otro usuario autenticado que
pide el mismo recurso recibe `404`.

### Corte 3 — observabilidad y accesibilidad

- **Aprobado por:** pendiente

Qué se registra y qué no (nunca datos personales sin enmascarar), y la accesibilidad de cada
pantalla.

## Estados de pantalla

Obligatorio para toda pantalla. Vacío y error no son el mismo estado: una consulta que
funcionó y no devolvió datos está vacía, no falló.

| Estado | Cuándo ocurre en esta pantalla | Qué muestra |
|---|---|---|
| Cargando | | |
| Con contenido | | |
| Vacío | | |
| Error | | |

## Reglas bajo prueba

Un caso por cada regla de negocio que esta funcionalidad podría romper.

| Regla | Caso que la cubre |
|---|---|

## Sin cubrir

Qué criterio o qué regla quedó sin caso, y por qué.

## Fuera de alcance

## Preguntas abiertas
