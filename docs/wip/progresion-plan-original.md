# Plan — corte vertical de progresión

## Objetivo

Hoy la progresión no existe como sistema: `GameEvents.ability_unlocked` y
`checkpoint_reached` están declaradas sin emisor ni suscriptor, `StatModifierNode` tiene
CERO instancias en escenas de producción (solo lo usan los tests), `SessionState` solo
reparte kits y `ZoneDoor` solo sabe de `required_players`. La mecánica del doble salto
YA está implementada (`locomotion.gd:53,92-96` lee `StatID.AIR_JUMPS` y gasta saltos
aéreos) y espera a que alguien cuelgue un modificador que nadie cuelga.

Se construye el bucle completo: pedestal → el host decide y replica → el estado vive en
un autoload → cada jugador cuelga el modificador → una puerta exige la habilidad.

## Decisión de diseño previa

Una habilidad es estado del **mundo**, no de la persona. Se deriva de lo ya decidido:
el guardado (ARCHITECTURE-MAP.md → Deferred) es "guarda el host, un archivo, estado del
mundo, sin guardado por jugador", y `ZoneDoor.required_players = 2` impide separar a los
jugadores entre zonas. Consecuencia: al desbloquear, la habilidad se aplica a AMBOS
jugadores.

## Archivos NUEVOS

1. `components/progression/ability_data.gd` — `class_name AbilityData extends Resource`
   - `@export var ability_id: StringName`
   - `@export var display_name: String` (para el aviso del HUD)
   - `@export var modifiers: Array[StatModifierData]`
   - §13: los datos del juego son un `Resource` con `@export`, como `AttackData`.

2. `components/progression/ability_modifier.gd` — `class_name AbilityModifier extends StatModifierNode`
   - `var ability: AbilityData`
   - `get_modifiers()` devuelve `ability.modifiers` (array vacío si es null).
   - Es un Nodo y no un RefCounted por §2: el día que una habilidad traiga hitbox o
     timer propios (dash), tiene dónde colgarlos.

3. `components/progression/ability_loadout.gd` — `class_name AbilityLoadout extends Node`
   - Cuelga de la entidad, hermano del `StatsComponent`. Lo encuentra con
     `ComponentLookup.find(get_parent(), "StatsComponent", "StatsComponent")`.
   - En `_ready`: aplica TODO lo que ya está desbloqueado en `WorldProgress` y luego se
     suscribe a `GameEvents.ability_unlocked`.
     Las dos cosas, y en ese orden, por la trampa documentada en AGENTS.md ("quien se
     suscribe tarde no ve el primer valor"): un jugador que aparece DESPUÉS del
     desbloqueo —el segundo peer al conectar, o un revivido— no oiría el evento pasado.
   - `grant(id)`: si ya está colgada, no hace nada (idempotente); si no, instancia un
     `AbilityModifier` con el `AbilityData` y lo añade como **hijo directo** del
     `StatsComponent` — `StatsComponent._recalculate` recorre `get_children()`, o sea
     solo hijos directos, así que colgarlo más abajo lo dejaría mudo.
   - No castea a `Player` ni asume su padre: sirve igual a un enemigo.

4. `autoloads/world_progress.gd` — autoload SIN `class_name` (como los otros tres; en
   Godot un `class_name` no puede coincidir con el nombre del autoload).
   - `# ephemeral: la progresión vive lo que la partida; el guardado la reconstruye`
     `var _unlocked: Dictionary = {}` — `StringName -> String` (ability_id → ruta del
     `.tres`). Se guarda la RUTA y no el recurso porque es lo que se puede replicar por
     RPC y lo que el guardado JSON escribirá (`ResourceSaver` está prohibido).
   - `has(ability_id) -> bool`, `data(ability_id) -> AbilityData` (hace `load` de la
     ruta), `unlocked_ids() -> Array[StringName]`, `clear()`.
   - `request_unlock(ability: AbilityData) -> void`: si `not multiplayer.is_server()`,
     return. El host también ve al cliente pisar el pedestal —su cuerpo está replicado y
     `position` viaja en modo ALWAYS—, así que nadie necesita pedirle permiso por RPC.
     Si es servidor: `rpc_unlock.rpc(id, path)`.
   - `@rpc("authority", "call_local", "reliable") func rpc_unlock(id, path)`: si ya
     estaba, return (idempotente); si no, lo guarda y emite `GameEvents.ability_unlocked`.
     El estado y el evento se emiten en el mismo sitio para que no diverjan (§4).
   - Sin sesión de red `multiplayer.is_server()` es `true` (OfflineMultiplayerPeer con
     id 1) y `rpc` con `call_local` se entrega localmente — es lo que ya hace
     `World.rpc_change_zone`, medido.

5. `level/systems/ability_pedestal.gd` — `@tool class_name AbilityPedestal extends Area2D`
   - `@export var ability: AbilityData`, `@export var size: Vector2`, dibujo de andamio
     y `_get_configuration_warnings()`, calcado de `ZoneDoor` (§13: la validación de
     contenido va en el editor).
   - `_on_body_entered`: si el cuerpo está en el grupo `zone_travellers` (no se castea a
     `Player`, igual que hace `ZoneDoor`), llama a `WorldProgress.request_unlock(ability)`.
     NO pregunta por la red: toda la disciplina de red vive en el autoload.
   - Se repinta al desbloquearse (escucha `GameEvents.ability_unlocked`) para que se vea
     que ya está cogido.

6. `components/progression/abilities/double_jump.tres` — `AbilityData` con
   `ability_id = &"double_jump"`, `display_name = "Doble salto"`, un
   `StatModifierData(AIR_JUMPS, +1, 1.0)`.

## Archivos MODIFICADOS

7. `components/stat_modifier_data.gd` — `extends RefCounted` → `extends Resource`, con
   `@export` en los tres campos.
   Motivo: sin esto un `AbilityData` no puede llevar sus modificadores dentro del `.tres`
   y habría que duplicar la clase en una versión Resource. Nadie muta un
   `StatModifierData` —`StatsComponent._recalculate` solo lee `stat_id`, `add_value` y
   `mult_value`—, así que compartir el recurso entre las dos instancias de jugador no
   reabre el fallo nº7 de AGENTS.md (sub-recursos compartidos que se ESCRIBEN). Se
   documenta en el archivo.

8. `level/systems/zone_door.gd` (187 líneas hoy) — `@export var required_ability: AbilityData`
   - En `_on_body_entered`, ANTES de emitir `traversal_requested`: si hay
     `required_ability` y `not WorldProgress.has(id)`, emite
     `blocked_changed(display_name)` y return.
   - Nueva señal `blocked_changed(ability_name: String)` para el HUD, en la misma línea
     que `waiting_changed`: la puerta existe también para decir POR QUÉ no se abre.
   - `_get_configuration_warnings` y `_draw` distinguen la puerta cerrada.

9. `ui/hud/hud.gd` (73) — `set_door_block(ability_name: String)`: pinta "Necesitas: X"
   en el mismo `Label` que el aviso de espera, o lo apaga con cadena vacía. El HUD sigue
   sin conocer a nadie: recibe un String ya resuelto (§5).

10. `systems/world/world.gd` (330) — tres puntos, vigilando §6 (tope duro 400):
    - En `_load_zone`, conectar/desconectar `door.blocked_changed` junto a
      `waiting_changed` (la desconexión importa: un `Area2D` que sale del árbol suelta
      sus `body_exited` y el aviso llegaría ya en la zona nueva).
    - `hud.set_door_block("")` al cargar zona, junto al `set_door_wait(0, 0)`.
    - `WorldProgress.clear()` en `_on_session_ended`.
    Si al terminar pasa de 400 líneas, se extrae el enganche del HUD a un método privado
    en vez de justificar el exceso.

11. `project.godot` — `WorldProgress="*res://autoloads/world_progress.gd"`.

12. `characters/player/player.tscn` — nodo `AbilityLoadout` colgado del `Player`.

13. `level/zones/zone_verdant.tscn`:
    - `AbilityPedestal` en `Rooms/Room4` (verdant_4, la cámara alta sobre el cruce; se
      llega subiendo la escalera desde verdant_2, que abre por los cuatro lados).
      Colocación medida, no a ojo: `RoomScaffold.floor_surface_y()` = `size.y*0.5 - 16` =
      624 para una sala de 1280, así que la base va a y=624 local. En x hay que esquivar
      tres cosas: el hueco del suelo (140 px centrado en x=0, porque Room4 abre por
      abajo), la escalera (losas en x ∈ [70, 410]) y las repisas izquierdas
      (`LEDGES`: x ∈ [-500, -80]). Queda x ∈ [-592, -500]: se coloca en x=-546.
    - `DoorToCinder` (`verdant_east`) pasa a exigir `double_jump`.
    Con esto el bucle es real: apareces en verdant_1 → cruce verdant_2 → subes a
    verdant_4, coges el doble salto → bajas → verdant_3 → la puerta abre.

14. `docs/adr/ARCHITECTURE-MAP.md` — filas de los cinco scripts nuevos + conteos
    actualizados de los modificados, en el MISMO commit (lo exige
    `tests/unit/test_architecture_map.gd`, que compara cada fila con el archivo real,
    falla si una clase de producción no está registrada y si algo pasa de 400 líneas).
    Retirar de `Deferred` lo que este lote cierra y añadir el disparador de lo que abre
    (habilidad con nodos propios → `AbilityData.node_scene`).

## Tests

15. `tests/unit/test_world_progress.gd` — estado, idempotencia (pisar dos veces el
    pedestal no cuelga dos modificadores), `clear()`, `data()` resuelve la ruta.

16. `tests/integration/test_progression.gd` — recorrido completo, no piezas sueltas:
    - Se MIDE la altura de salto antes y después del desbloqueo conduciendo a un jugador
      real con `ScriptedIntentSource` (el patrón de `test_room_traversal.gd`), y se
      exige que suba. No se comprueba "el stat vale 1".
    - DOS jugadores: ambos reciben la habilidad. (AGENTS.md: "un fallo que solo aparece
      con dos, no aparece con uno".)
    - Un jugador que entra al árbol DESPUÉS del desbloqueo también la tiene — es el
      caso del suscriptor tardío.
    - La puerta con `required_ability` no emite `traversal_requested` sin la habilidad y
      sí la emite después; y avisa por `blocked_changed`.
    - El pedestal cae DENTRO de verdant_4 y su base se apoya en la superficie del suelo
      que devuelve el andamio (contra el fallo nº4: geometría que nadie mide).

## Verificación final

- Suite completa por línea de comandos, mirando el conteo de **Scripts** y no el mensaje
  "All tests passed" (GUT omite en silencio los scripts que no compilan).
- `godot --headless --import --path .` tras crear las clases nuevas: un `class_name` que
  no está en el caché de clases globales deja SIN script a quien lo use, la escena se
  instancia igual y la suite sigue verde (trampa nº1 y nº9 de AGENTS.md).
- Partida REAL de host + cliente con `--write-movie`, contando los PNG escritos, con el
  panel F3 encendido: pisar el pedestal en un peer y comprobar que el OTRO también salta
  dos veces, y que la puerta se abre para los dos.

## Fase 2 (después, y solo documentación)

Un stress test de arquitectura: 10 preguntas del tipo "si quiero añadir natación, ¿está
el juego listo?", "¿y varias fuentes de input (mando, teclado, ratón)?". Se responde por
escrito en un documento nuevo bajo `docs/adr/`, con veredicto y evidencia en archivo:línea
por cada una. NO se toca código en esa fase.
