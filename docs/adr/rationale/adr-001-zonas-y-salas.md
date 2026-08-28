# ADR-001 — La unidad de carga es la zona, no la sala

| Campo   | Valor                    |
| ------- | ------------------------ |
| Estado  | **Aceptada**             |
| Fecha   | 28 de agosto de 2026     |
| Ámbito  | `systems/world/`, `level/`, `systems/camera/` |

---

## Contexto

Sword & Shield es un metroidvania de dos jugadores **solo en red**. Cada cliente lleva su
propia cámara siguiendo a su personaje, de modo que los dos jugadores pueden estar en
puntos distintos del mundo al mismo tiempo. Esa es una decisión ya tomada, y es la que
condiciona todo lo demás.

La palabra "sala" se usa habitualmente para dos cosas distintas que aquí conviene separar:

| Concepto        | Qué es                          | Implementación                                        | ¿Se carga? |
| --------------- | ------------------------------- | ----------------------------------------------------- | ---------- |
| **Sala** (room) | Unidad de **diseño y de cámara**. Lo que el jugador percibe como un lugar. | Región lógica dentro de una zona: un `Area2D` con sus límites. | No |
| **Zona** (zone) | Unidad de **carga**. Del orden de 10 a 30 salas. | Una escena que se carga y se descarga entera.          | Sí |

La zona es lo que en Super Metroid son Crateria, Norfair o Maridia, y en Hollow Knight
Cruces Olvidados, Sendas Verdes o Yermos Fúngicos.

La pregunta que este ADR responde es dónde se pone el punto de carga: en la sala —el
modelo clásico del género— o en la zona.

---

## Decisión

**La zona es la unidad de carga. La sala no se carga ni se descarga.**

Dentro de una zona no ocurre carga alguna. Los jugadores se mueven libremente, se separan
cuanto quieran, y al cruzar la frontera de una sala lo único que cambia son **los límites
de la cámara** (`PlayerCamera.apply_room_bounds(Rect2)`). Entre zonas sí hay un punto de
carga real, y es el único.

### 1. El argumento principal: complejidad de red

Cargar y descargar por sala, con dos jugadores independientes en red, convierte un
problema continuo en una fuente permanente de casos raros:

- El jugador A cruza una puerta mientras B sigue a mitad de la sala anterior. ¿Quién
  descarga qué?
- Los enemigos de una sala que un jugador todavía ocupa: ¿se descargan, se congelan, se
  replican a un peer que ya no los ve?
- A vuelve tres segundos después. ¿Se reconstruye el estado o se reinicia?

Cada uno de esos casos es un bug de desincronización esperando. Y no son casos límite:
con dos jugadores explorando, ocurren en cada minuto de partida. Con la zona como unidad
de carga, esa misma complejidad no desaparece pero se **concentra en un evento raro y
discreto** — el cambio de zona—, que se puede tratar como una transición explícita en vez
de como un flujo continuo.

### 2. En 2D el presupuesto de memoria da de sobra

Hollow Knight separa escenas por el peso del **arte**, no por la geometría. Un
`TileMapLayer` de 200×100 celdas es un diccionario de veinte mil entradas: trivial.

```
200 × 100 celdas  →  ~20.000 entradas de diccionario  →  irrelevante
```

Lo caro son las texturas únicas, los enemigos instanciados y las luces. Y precisamente eso
queda acotado por zona sin esfuerzo: una zona comparte paleta, tileset y bestiario.

### 3. Salas grandes y carga-por-sala tiran en direcciones opuestas

La preferencia de diseño del proyecto son las salas grandes. Si las salas son grandes hay
menos salas por zona, lo que hace la carga por zona **aún más holgada**. Es decir: la
preferencia de diseño no compite con la decisión, la refuerza.

### 4. El cambio de zona es un momento de diseño aprovechable

Al ser un evento discreto, se puede exigir que **ambos jugadores estén en la puerta** para
cambiar de zona. En un cooperativo eso es defendible como norma de juego —marca el fin de
un tramo— y de paso elimina de raíz el caso "cada jugador en una zona distinta", que en
red es el más caro de todos.

---

## Alternativas consideradas

| Alternativa | Por qué se descartó |
| ----------- | ------------------- |
| **Carga y descarga por sala** (modelo Super Metroid / Hollow Knight) | Es el modelo correcto para un juego de **un solo jugador**, donde solo hay una cámara y una posición que consultar. Con dos jugadores independientes en red produce la clase de casos raros descrita arriba, de forma continua y no acotada. |
| **Mundo entero en memoria, sin zonas** | El presupuesto deja de ser acotado y predecible en cuanto el arte crece: no hay techo que defender. Además no ofrece ningún punto natural de carga para el día en que haga falta uno, así que introducirlo más tarde sería un cambio estructural, no un ajuste. |

---

## Consecuencias

**No hay nada que deshacer en lo ya construido.** `PlayerCamera.apply_room_bounds(Rect2)`
funciona exactamente igual si la sala es una escena cargada o una región de un mundo
mayor: recibe un `Rect2` y encierra la cámara en él. La decisión no estaba acoplada al
código existente, y por eso ha podido tomarse tarde sin coste.

**Se abre un problema nuevo: la dispersión.** Si los jugadores se separan libremente
dentro de una zona, uno puede irse a la otra punta. Eso es bueno para la exploración y
potencialmente malo para el cooperativo. Hará falta un **mecanismo de reagrupamiento**; el
candidato natural es el tether, ya reconvertido en "salto largo accionable", que sirve a
la vez de herramienta de movimiento y de vía de reunión.

**Ritmo de diseño: salas todas grandes cansa.** Los metroidvania buenos alternan pasillos
de conexión cortos, cámaras amplias de combate y salas verticales altas. El ritmo lo da el
**contraste**, no el tamaño medio. Que la sala sea barata —una región, no una escena—
facilita justamente eso: mezclar tamaños dentro de una misma zona no tiene coste técnico.

**Requisito específico de este juego: los kits son asimétricos.** Espada y escudo hacen
cosas distintas, así que una sala de un solo carril convierte a uno de los dos jugadores
en pasajero. Las salas necesitan **espacio o rutas alternativas** para que cada rol tenga
algo que hacer; es una restricción de diseño de nivel, no un detalle de implementación.

---

> **Revisión.** Este ADR se revisa si aparece modo competitivo —el reparto de carga entre
> peers cambia de premisas— o si el presupuesto de memoria por zona se convierte en un
> problema **real y medido**, no supuesto.
