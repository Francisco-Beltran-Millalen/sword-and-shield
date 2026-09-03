# Progresión — trabajo a medias, cómo retomarlo

**Estado: INCOMPLETO. La suite NO se ha vuelto a correr desde el último cambio.**
Baseline antes de empezar: 20 scripts, 214 tests, 214 pasando (`caa844c`).

Se paró por límite de contexto, no por un problema técnico. Lo que hay en este commit
son tres scripts nuevos que **todavía no compilan solos**: `ability_loadout.gd` nombra
`WorldProgress`, que aún no existe como autoload. Eso deja el nodo SIN script y la suite
en verde igual — la trampa nº1 de `CLAUDE.md`. No dar nada por bueno hasta terminar la
lista de abajo y volver a medir.

## Qué se decidió y por qué (no re-litigar)

Lee `progresion-plan-original.md` y sobre todo `progresion-critica-y-triaje.md`: un
revisor sin contexto encontró 14 objeciones contra el código real, TODAS confirmadas, y
el triaje de cada una está escrito ahí. Lo esencial:

- Una habilidad es progreso del **mundo**: al desbloquearse la tienen los dos jugadores.
  Se deriva del guardado ya decidido (host, un archivo, estado del mundo) y de
  `required_players = 2`.
- Por la red y al guardado viaja **solo el `ability_id`**, nunca una ruta de recurso:
  `load()` sobre una ruta que venga de disco es ejecución de código arbitrario, que es
  justo lo que la fila del guardado en `ARCHITECTURE-MAP.md` prohíbe.
- **Un solo nodo** (`AbilityLoadout extends StatModifierNode`) en vez de un nodo por
  habilidad: `StatsComponent._recalculate` recorre `get_children()` y llama a
  `get_modifiers()`, así que un hijo con N modificadores es indistinguible de N hijos.
  Evita colgar nodos desde el `body_entered` de un pedestal (dentro del flush de física).
- El `AbilityLoadout` **no guarda copia** de lo desbloqueado: lo consulta al recalcular.
  Por eso un jugador que aparece tarde no se pierde nada.

## Hecho (en este commit)

- `components/progression/ability_data.gd` — `AbilityData` (Resource): `ability_id`,
  `display_name`, `modifiers: Array[StatModifierData]`.
- `components/progression/ability_catalogue.gd` — `AbilityCatalogue` (Resource):
  `abilities` + `find(id)`. Recurso explícito y no barrido de directorio: `DirAccess`
  sobre `res://` no es fiable en un build exportado.
- `components/progression/ability_loadout.gd` — `AbilityLoadout` (StatModifierNode).

## Falta (en orden)

1. `components/stat_modifier_data.gd`: `extends RefCounted` → `extends Resource`, con
   `@export` en los tres campos. Dejar `stat_id` como `int` y NO como
   `StatsComponent.StatID`: ese tipo crea una referencia cíclica entre class_names.
   Documentar que nadie muta un `StatModifierData` (solo se leen los tres campos en
   `stats_component.gd:113-121`), así que compartir el recurso entre las dos instancias
   de jugador no reabre el fallo nº7 de `CLAUDE.md`.
2. `autoloads/world_progress.gd` — autoload SIN `class_name`. Estado
   `# ephemeral` `_unlocked: Array[StringName]`. `has(id)`, `granted() -> Array[AbilityData]`,
   `unlocked_ids()`, `clear()`, `request_unlock(id)` (si `not multiplayer.is_server()`,
   return — el host ve al cliente pisar el pedestal porque `position` se replica en
   ALWAYS) y `@rpc("authority", "call_local", "reliable") rpc_unlock(id)`, que guarda y
   emite `GameEvents.ability_unlocked`. Estado y evento en el mismo sitio (§4).
   Precedente de RPC en autoload: `network_manager.gd:203,263`.
3. `project.godot`: `WorldProgress="*res://autoloads/world_progress.gd"`.
4. `components/progression/abilities/double_jump.tres` (+`catalogue.tres`):
   `ability_id = &"double_jump"`, `display_name = "Doble salto"`, un
   `StatModifierData(AIR_JUMPS, +1, 1.0)`. La mecánica YA existe:
   `locomotion.gd:53,92-96` lee `AIR_JUMPS` y gasta saltos aéreos.
5. `level/systems/ability_pedestal.gd` — `@tool class_name AbilityPedestal extends Area2D`,
   calcado de `ZoneDoor` (dibujo de andamio + `_get_configuration_warnings`). Al entrar un
   cuerpo del grupo `zone_travellers` llama a `WorldProgress.request_unlock(...)`; no
   pregunta por la red. **Toda lectura del autoload y toda suscripción van DESPUÉS del
   `if Engine.is_editor_hint(): return`**: un autoload no se instancia en el editor y un
   `@tool` que lo nombre en `_draw` da `null` en cada repintado. Su aviso de
   configuración debe exigir que su `ability_id` esté en el catálogo.
6. `level/systems/zone_door.gd`: `@export var required_ability: AbilityData` y la firma
   de `waiting_changed` pasa a `(present, required, blocked_by: String)` — UN solo
   escritor del Label del HUD. Con dos métodos hay carrera: P1 entra, P2 entra (bloqueada),
   **P1 sale** y `zone_door.gd:187` reemite y pisa el aviso, con lo que la puerta miente
   sobre por qué no se abre.
7. `ui/hud/hud.gd`: `set_door_wait(present, required, blocked_by := "")` pinta
   "Necesitas: X" cuando hay bloqueo. Actualizar `test_hud.gd`.
8. `systems/network/lobby.gd:19-21`: `WorldProgress.clear()` junto a `SessionState.clear()`.
   NO en `World._on_session_ended`: con Esc y sin sesión (`world.gd:53-64`) se cambia de
   escena y se retorna sin emitir `session_ended`.
9. `level/systems/zone.gd:115`: ampliar el barrido de avisos de `CharacterBody2D` a
   `Area2D` (excluyendo `RoomBounds`). Sin esto un pedestal en coordenadas de mundo bajo
   una sala que ya tiene `position` cae en otra sala sin un solo aviso — el fallo de los
   tres enemigos otra vez.
10. `characters/player/player.tscn`: `AbilityLoadout` colgado **bajo `StatsComponent`**.
11. `level/zones/zone_verdant.tscn`: pedestal a ras de suelo en verdant_1 o verdant_2,
    **NO en verdant_4** (`openings = 2`, solo abre por abajo, y
    `test_room_traversal.gd:78-116` mide esa travesía en 11 de 16 intentos: no es sitio
    para el camino crítico). Geometría real de una sala de 1280: suelo en y=+624
    (`floor_surface_y()`), pared interior en x=**-624**, repisas en [-500,-80] y
    **[-550,-250]**, escalera en [70,410] y [200,540], hueco del suelo 140 px centrado en
    x=0. Hueco libre: x ∈ (-624, -550), centro ≈ **-587**. No fijarlo por aritmética:
    hay 4 px de holgura al pasar bajo la repisa 1 (cara inferior en suelo-48, cuerpo de
    44), así que el test tiene que **conducir** a un jugador hasta el pedestal.
    Y `DoorToCinder` (`verdant_east`) pasa a exigir `double_jump`.
12. **Aislamiento de los tests, imprescindible:** `WorldProgress.clear()` en
    `IntegrationHarness.setup()`. `WorldProgress` es un autoload de proceso y GUT no lo
    reinicia entre archivos: sin esto un desbloqueo filtrado sube la altura de salto
    medida en `test_room_traversal.gd:34-53` y ese test pasaría con una escalera
    insubible, y `test_player_movement.gd:85` sumaría dos saltos aéreos en vez de uno.
13. Los **seis** tests de `test_zone_travel.gd` (:60, :72, :82, :96, :119) usan
    `doors()[0]`, que es `DoorToCinder`: hay que desbloquear explícitamente en su
    preparación. Si no, la suite queda verde o roja **según el orden de los archivos**.
14. `tests/unit/test_world_progress.gd` y `tests/integration/test_progression.gd`:
    - medir la altura de salto antes/después conduciendo un jugador real, no leer el stat;
    - DOS jugadores, ambos la reciben;
    - un jugador que entra al árbol DESPUÉS del desbloqueo también la tiene;
    - la puerta no cruza sin la habilidad y sí después, y avisa por `waiting_changed`;
    - cargar `double_jump.tres` **de disco** y afirmar `modifiers.size() == 1` (un `.tres`
      mal escrito deserializa el array vacío y todo lo demás parece funcionar);
    - localizar el pedestal **por tipo** (`find_children("*", "AbilityPedestal", …)`), no
      por nombre: por nombre pasaría aunque el script no compile.
15. `docs/adr/ARCHITECTURE-MAP.md` en el MISMO commit: filas de los scripts nuevos,
    conteos de los modificados, y **reescribir** la fila de `stat_modifier_data.gd`, que
    hoy dice "`RefCounted` de datos". Lo exige `tests/unit/test_architecture_map.gd`.

## Verificación (no negociable)

- `godot --headless --import --path .` tras crear los `class_name` nuevos, o los scripts
  que los usan no compilan y los nodos se quedan sin script en silencio.
- Suite completa mirando el conteo de **Scripts**, no el "All tests passed".
- Partida REAL de host + cliente con `--write-movie` y el panel F3 encendido: pisar el
  pedestal en un peer y comprobar que el OTRO también salta dos veces y que la puerta se
  abre para los dos.

## Pendiente aparte (fase 2, solo documentación)

Stress test de arquitectura: 10 preguntas del tipo "¿está el juego listo para añadir un
motor de nadar?", "¿y varias fuentes de input (mando, teclado, ratón)?", respondidas por
escrito con veredicto y evidencia en archivo:línea, sin tocar código. No empezada.
