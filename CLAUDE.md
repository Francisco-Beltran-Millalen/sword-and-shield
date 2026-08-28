# Sword and Shield — contexto del proyecto

Plataformero **metroidvania de 2 jugadores en red**, con kits asimétricos: un jugador
lleva espada, el otro escudo. Godot 4.7, GDScript con tipado estático obligatorio.

Sucede al proyecto `../geometry-tension` ("Tension"), que quedó **pausado** el 28 de
agosto de 2026. De allí se portó la infraestructura genérica; el juego en sí se descartó.

---

## Comandos

```bash
# Tests (no hay escena runner: se invoca GUT por línea de comandos)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Un solo archivo de test
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_combat.gd -gexit

# Probar la red sin dos máquinas (los `--` separan los argumentos del juego)
godot -- --host          # terminal 1
godot -- --join 127.0.0.1   # terminal 2
```

---

## Cómo trabajar aquí

**Preferencia explícita del dueño: que el motor haga el trabajo, no el código propio.**
Antes de escribir lógica a mano, busca la feature nativa de Godot. El proyecto anterior
acumuló deuda justo por lo contrario. Está formalizado como **§13 — El motor primero** en
`docs/adr/CONSTITUTION.md`, con una tabla de casos concretos.

**El objetivo actual es la estructura del proyecto, no el contenido del juego.** Se busca
código reutilizable y desacoplado: componentes que sirvan igual a un jugador, un enemigo o
una trampa. Un componente que castee a `Player` o asuma quién es su padre está mal.

Lee `docs/adr/CONSTITUTION.md` antes de cambios de arquitectura. Sus dos enmiendas
importantes, ambas nacidas de deuda real del proyecto anterior:

- **§2 — una capacidad es un Nodo, nunca un `RefCounted`.** Sin esto no puede tener
  hijos (hitbox, `AnimationPlayer`, timers), y su estado acaba en el anfitrión.
- **§6 — 400 líneas es tope duro,** no una invitación a justificarse. En el proyecto
  anterior el umbral "blando" dejó archivos de 1.000 líneas con párrafos explicando por
  qué podían crecer más.

`docs/adr/ARCHITECTURE-MAP.md` se actualiza **en el mismo commit** que el código. Ya no
depende de acordarse: `tests/unit/test_architecture_map.gd` compara cada fila con el
archivo real y falla en rojo si el mapa miente, si una clase de producción no está
registrada o si alguien pasa de 400 líneas (§6).

---

## Trampa recurrente: verde no significa funcionando

Ha pasado **cuatro veces** en este proyecto. Los tests pasaban y la funcionalidad no existía:

1. `room_scaffold.gd` no compilaba. Un error de parseo deja al nodo **sin script** sin
   romper la instanciación de la escena: las salas quedaban sin suelo y la suite seguía
   en verde.
2. Los `AnimationPlayer` estaban vacíos, así que nadie llamaba a `Hitbox.enable()` y la
   espada no hacía daño. Los tests de `Hitbox` aislada pasaban igual.
3. Faltaba que la `Hitbox` llamara a `Hurtbox.receive()`. La cadena quedaba abierta: la
   ventana se abría y el daño no llegaba a aplicarse nunca.
4. `RoomScaffold` dibujaba el hueco de paso a 514 px del suelo y las plataformas a 401,
   contra un salto de 101. Las dos zonas eran intransitables: el jugador caía en la
   primera sala y no podía salir. El juego arrancaba sin un solo error y la suite daba
   119/119, porque **ningún test conducía a un jugador por la geometría**.

**Consecuencias prácticas:**

- **GUT omite en silencio los scripts que no compilan** y aun así imprime *"All tests
  passed"*. La señal fiable es el conteo de **Scripts**, no el mensaje final.
- Prueba recorridos completos, no piezas sueltas. `tests/integration/test_damage_chain.gd`
  es el modelo: va de la intención al descuento de salud, y
  `tests/integration/test_room_traversal.gd` conduce a un jugador real por la sala.
- **Mide, no deduzcas.** El alcance del jugador se mide conduciéndolo, y la geometría se
  compara contra esa medida. Tres diseños de escalera pasaron la aritmética y se atascaron
  al pilotarlos: el desplazamiento lateral que cabe en un salto no es el que parece.
- **Ejecuta el juego de verdad** antes de dar algo por terminado. Los tres primeros
  fallos aparecieron al lanzar host y cliente, no en la suite. El cuarto ni siquiera:
  arrancaba limpio en ambos extremos y solo salió al medir la geometría contra el
  alcance del jugador.

---

## Decisiones tomadas

| Decisión | Por qué |
| --- | --- |
| **Solo multijugador en red.** No hay cooperativo local en sofá | Cada cliente controla un personaje; por eso el InputMap tiene un solo juego de acciones, sin prefijo `p1_`/`p2_` |
| **Cámara por cliente**, colgada del personaje y encendida solo en su peer | Permite que los dos jugadores estén en sitios distintos, que es lo que hace viable la exploración divergente |
| **Autoridad por jugador**: cada peer simula el suyo y replica | Elimina el reenvío de intent por RPC del proyecto anterior, que metía ida y vuelta en cada pulsación. Un `Player` sin autoridad hace `return` en `_physics_process` |
| **La zona es la unidad de carga; la sala solo encuadra** | Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`. Cargar por sala con dos jugadores independientes es una fuente permanente de desincronización |
| **Kits fijos, repartidos por `peer_id`** (host = espada) | Determinista: cada cliente lo calcula solo, no se replica. Un desajuste es imposible por construcción |

Antes de preguntar por la autoridad de red, comprueba `multiplayer.has_multiplayer_peer()`:
tras una desconexión la escena vive unos frames sin peer y consultar ahí es un error de
motor.

---

## Mapa rápido

```
components/          Reutilizables, sin conocer a su dueño
  combat/            AttackData (Resource) · Attacker · DamageReceiver
  hitbox · hurtbox · guard_box · health_component · stats_component · state_machine
characters/player/   Player (orquestador delgado) · Locomotion · IntentSource
  kits/              PlayerKit (Nodo) → SwordKit · ShieldKit
characters/enemy/    Enemy · EnemyArchetype (Resource) · AIIntentSource · Perception
  archetypes/        Un .tres por tipo de enemigo
level/systems/       Zone · RoomBounds · ZoneDoor · RoomScaffold (todos @tool)
level/zones/         zone_verdant · zone_cinder (5 salas cuadradas cada una)
systems/             world/ · network/ (lobby, session) · camera/
autoloads/           NetworkManager · GameEvents · SessionState
```

**Patrones a imitar** (los mejores del repo): `stats_component.gd` descubre sus
modificadores solo con `child_entered_tree` — desbloquear una habilidad es colgar un nodo.
`zone.gd` busca por **tipo** (`find_children("*", "RoomBounds")`), no por nombre.
`IntentSource` se sustituye por nodo, así que los tests conducen a un jugador real sin
tocar `Input`.

**El enemigo no estrena ningún sistema.** Usa `Locomotion`, `Attacker`, `Hitbox`,
`Hurtbox`, `DamageReceiver`, stats y salud del jugador sin una línea añadida para él; lo
único propio es `AIIntentSource`, que rellena el mismo `PlayerIntent` que el teclado. Si
para meter una entidad nueva hiciera falta escribir movimiento o combate propios, el
problema no es la entidad: son los sistemas, que estaban acoplados al jugador.

**Un `class_name` nuevo no existe hasta que Godot reimporta.** Crear el archivo desde
fuera del editor no lo registra en el caché de clases globales: los scripts que lo usan no
compilan, el nodo se queda **sin script** y la escena se instancia igual. Tras añadir una
clase, `godot --headless --import --path .`. Y para lanzar un script suelto hace falta
`--path .`, o los autoloads no se registran y pasa lo mismo.

**`GameEvents` no es un atajo.** Un evento entra ahí solo si emisor y receptor no pueden
conocerse por el árbol. Si se conocen, va una señal local con `bind` — las condiciones
están escritas en el propio archivo.

---

## Qué falta

Por orden de lo que más desbloquea:

1. **HUD.** `ui/hud/` vacía. Sin él no se ve la salud ni por qué una puerta no se abre
   (`ZoneDoor` ya emite `waiting_changed`), lo que dificulta evaluar el juego en pruebas.
2. **Progresión.** El mecanismo existe (`StatModifierNode`); faltan las habilidades y las
   puertas que las exijan.
3. **Guardado.** No hay nada: ni `ResourceSaver`, ni `user://`. Es el corazón del género.
4. **Mapa.**
5. **Tileset y arte.** Todo son `Polygon2D`. `RoomScaffold` es geometría provisional y
   está marcado para retirarse cuando haya `TileMapLayer` con terrain sets.
6. **Audio.** Nada.

También pendientes, anotados con su disparador en `ARCHITECTURE-MAP.md` → *Deferred*:
`tether_pressed` e `interact_pressed` viajan en el intent pero **nadie los consume** (el
salto largo y la interacción); `DAMAGE_POWER` y `KNOCKBACK_DEALT` están declarados en los
stats y nadie los lee — cuando se implementen van en el `Attacker`, no en la entidad; y un
mecanismo de reagrupamiento por si la dispersión dentro de una zona molesta en pruebas.
