# Crítica del subagente al plan de progresión (2 sep 2026) + triaje

Baseline antes de tocar nada: 20 scripts, 214 tests, 214 pasando.

## Objeciones (verbatim del revisor, resumidas a lo verificable)

1. **`DoorToCinder` es la puerta de casi todos los tests de cruce.** `test_zone_travel.gd:40`
   hace `world.current_zone.doors()[0]` y Verdant tiene UNA sola puerta
   (`zone_verdant.tscn:147-158`). Exigirle `double_jump` rompe seis tests (:60, :72, :82,
   :96, :119). Peor: `WorldProgress` es un autoload de proceso y GUT no lo reinicia entre
   archivos — si `test_progression.gd` corre antes y deja el desbloqueo puesto, los seis
   PASAN. La suite se vuelve verde o roja según el orden de los archivos.
2. **La misma contaminación falsea los tests que miden geometría.** Con `AbilityLoadout` en
   `player.tscn`, un desbloqueo filtrado sube la altura de salto medida en
   `test_room_traversal.gd:34-53` y el test de "la subida cabe en un salto" pasaría con una
   escalera insubible. `test_player_movement.gd:85` ya cuelga un `AbilityUnlock.air_jumps(1)`:
   sumaría dos.
3. **`clear()` en `World._on_session_ended` no cubre la salida sin sesión.** `world.gd:53-64`:
   con Esc y sin sesión se hace `change_scene_to_file` y se retorna, sin emitir `session_ended`.
   El precedente correcto es `lobby.gd:19-21`, que ya hace `NetworkManager.reset()` +
   `SessionState.clear()` en su `_ready`.
4. **Guardar la RUTA del `.tres` contradice la decisión de guardado ya escrita.**
   `ARCHITECTURE-MAP.md` (fila *Sistema de guardado*): "Nunca `ResourceSaver`: un `.tres` puede
   referenciar un script → ejecución de código arbitrario". Una ruta en el JSON + `load()` es el
   mismo agujero con otro envoltorio. Guardar solo `ability_id` y resolverlo contra un catálogo.
5. **Los números de colocación están mal.** `LEDGES` son DOS: [-500,-80] y **[-550,-250]**. El
   plan solo contó la primera y puso el pedestal en x=-546, DENTRO de la segunda. La cara
   interior de la pared está en **-624**, no en -592. Hueco real: x ∈ (-624, -550), 74 px,
   centro ≈ -587. Además, caminando hacia allí se pasa bajo la repisa 1 con **4 px de holgura**
   (cara inferior en suelo-48, cuerpo de 44).
6. **Un `Area2D` mal colocado no tiene red de seguridad.** `zone.gd:115` solo barre
   `CharacterBody2D`. Un pedestal en coordenadas de mundo bajo `Rooms/Room4` (que ya lleva
   `position`) caería en otra sala sin un solo aviso — el fallo de los tres enemigos, otra vez.
7. **`set_door_block` y `set_door_wait` escribirían el mismo Label sin árbitro (§4).** Secuencia:
   P1 entra (esperando 1/2) → P2 entra (bloqueada: "Necesitas X") → **P1 sale** →
   `zone_door.gd:187` reemite `waiting_changed` y pisa el aviso. La puerta miente sobre por qué
   no se abre, que es justo lo que `zone_door.gd:166-168` promete que no pasa.
8. **`@tool` + autoload.** Ningún `@tool` del repo toca un autoload en el editor;
   `room_bounds.gd:175` lo hace tras el `return` de `is_editor_hint()`. Un autoload no se
   instancia en el editor → `null` en cada repintado.
9. **Un `AbilityData` creado inline en el inspector queda empotrado en el `.tscn`** y su
   `resource_path` lleva `::`; el otro peer no lo resuelve y el stat no cambia, en silencio.
10. **`add_child` dentro de `body_entered`** es inocuo con un Node pelado y deja de serlo el día
    del dash con hitbox: "Can't change this state while flushing queries".
11. **Alternativa más simple: un solo nodo.** `AbilityLoadout extends StatModifierNode` bajo el
    `StatsComponent`; `get_modifiers()` concatena lo desbloqueado y emite `modifier_changed`.
    `stats_component.gd:113-121` recorre `get_children()` y llama `get_modifiers()`: un hijo que
    devuelve N modificadores es indistinguible de N hijos. Elimina `ability_modifier.gd`, la
    idempotencia, el add_child lateral y el problema 10.
12. **verdant_4 solo abre por abajo** (`zone_verdant.tscn:177`, `openings = 2`) y
    `test_room_traversal.gd:78-116` mide esa travesía en **11 de 16 intentos**. No poner ahí el
    camino crítico de la progresión.
13. **Ningún test cazaría un `AbilityPedestal` que no compile**: `test_zone_depth.gd:206-221`
    solo mira `Hud` y `DebugOverlay` de `world.tscn`. Buscarlo por TIPO, no por nombre.
14. **Un `.tres` cuyo `modifiers` deserialice vacío** es la trampa nº2 con otro traje: cargar el
    recurso DE DISCO en el test y afirmar `modifiers.size() == 1`, además de medir el salto.

## Lo que el revisor verificó como correcto

- RPC sobre autoload: precedente real en `network_manager.gd:203,263`.
- `rpc()` con `call_local` sin sesión se entrega localmente (`world.gd:186`, ejercitado).
- El host SÍ ve al cliente pisar el pedestal: `player.tscn:19-22` replica `position` en ALWAYS.
- `_init` con argumentos por defecto sigue siendo cargable como `Resource`; no rompe
  `test_stats_component.gd:32` ni `tests/helpers/ability_unlock.gd:20-23`.
- `floor_surface_y()` = 624 ✓; hueco del suelo = 140 px centrados en x=0 ✓.
- `GameEvents.ability_unlocked` cumple las tres condiciones de admisión del bus.
- Ningún archivo pasa de 400 líneas con lo añadido (world 330, zone_door 187, hud 73).
- OJO: `shield_kit.gd:12` dice en un comentario que la guardia "se expresa como un
  `StatModifierNode`" — es FALSO, usa `speed_scale()`. Comentario rancio, no citarlo.

## Triaje (con el contexto completo)

CONFIRMADAS y cómo cambia el plan:

- **1 y 2 → el aislamiento se arregla de raíz, no moviendo la puerta.** `required_ability` SE
  QUEDA en `verdant_east`: es la única salida y bloquearla es el bucle del género. Se añade
  `WorldProgress.clear()` en `IntegrationHarness.setup()` (cubre de golpe todos los tests de
  integración) y los seis tests de cruce desbloquean explícitamente en su preparación, lo que
  además documenta que la puerta ahora tiene llave.
- **3 →** `clear()` va en `lobby.gd:_ready`, junto a `SessionState.clear()`. Cubre las tres
  formas de volver al lobby.
- **4 → aceptada, con catálogo precargado y no barrido de directorio.** `DirAccess` sobre
  `res://` no es fiable en un build exportado (los `.tres` viajan como `.remap`). Se añade
  `components/progression/ability_catalogue.gd` (Resource) + `abilities/catalogue.tres`, que
  `WorldProgress` precarga por ruta constante. Por el cable viaja SOLO el `ability_id`; nada que
  venga de disco o de la red se pasa a `load()`.
- **5 → corregida:** pedestal a x ≈ -587. Y la colocación NO se fija por aritmética: un test
  conduce a un jugador desde el punto de aparición hasta el pedestal y exige que lo alcance
  (los 4 px de holgura bajo la repisa se miden, no se deducen).
- **6 →** ampliar el barrido de `Zone._get_configuration_warnings` a `Area2D`, excluyendo
  `RoomBounds`. Dos líneas.
- **7 → un solo escritor del Label:** se extiende la firma existente a
  `waiting_changed(present, required, blocked_by: String)` y `hud.set_door_wait(...)` con el
  tercer parámetro. Sin segundo método, sin carrera. Toca `test_hud.gd`.
- **8 →** el pedestal pinta su estado desde una variable propia; toda suscripción y toda lectura
  del autoload van tras el `if Engine.is_editor_hint(): return`.
- **9 →** se disuelve con el catálogo: el `_get_configuration_warnings` del pedestal exige que su
  `ability_id` esté en el catálogo.
- **10 y 11 → aceptada la alternativa simple.** `AbilityLoadout extends StatModifierNode` bajo el
  `StatsComponent`. Desaparecen `ability_modifier.gd`, el `add_child` en el callback de física y
  la lógica de idempotencia. §2 no se viola: hoy una habilidad son números, y el disparador de
  `AbilityData.node_scene` queda anotado en Deferred.
- **12 →** el pedestal NO va a verdant_4. Va a verdant_1/verdant_2, a ras de suelo, fuera del
  punto de aparición.
- **13 →** el test localiza el pedestal por tipo (`find_children("*", "AbilityPedestal", …)`).
- **14 →** el test carga `double_jump.tres` de disco y afirma `modifiers.size() == 1`.

Ninguna descartada por completo. Las dos matizadas: la 4 (catálogo `.tres` precargado en vez de
barrido de directorio) y la 12 (se disuelve al mover el pedestal).
