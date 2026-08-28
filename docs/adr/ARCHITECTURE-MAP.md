# Mapa de Arquitectura

Registro de lo que **existe** en el proyecto: una fila por clase construida, con su
superficie pública y las cláusulas de la constitución que la gobiernan.

> **Nota de mantenimiento — obligatoria.**
> Este documento se actualiza en el **mismo commit** que el código que describe. No en el
> siguiente, no "cuando cuadre". Un mapa desactualizado es peor que no tenerlo: en el
> proyecto anterior registraba 793 y 729 líneas para archivos que ya iban por 1.000 y 972,
> y a partir de ahí nadie volvió a confiar en él. Si un cambio no cabe en la fila, la fila
> se reescribe.
>
> Reglas de la entrada:
> - **Superficie pública** = solo lo que otros nodos pueden llamar o leer. No es un
>   changelog; no se acumulan párrafos históricos.
> - Si una fila crece más de unas pocas líneas, el problema suele ser la clase, no la fila.
> - Las excepciones al límite de 400 líneas (§6) se registran **aquí**, con fecha y
>   condición de salida (`se divide cuando X`). Una excepción cuya condición ya se cumplió
>   es una violación.

---

## Built

| Clase | Ruta | Superficie pública | Cláusulas de la constitución |
| ----- | ---- | ------------------ | ---------------------------- |
| `Player` | `characters/player/player.gd` (221) | Entidad. `equip_kit(scene)`, `apply_impulse(v)` — **única** vía para que algo externo lo mueva, `place_at(point)`, `revive_full()`, `get_facing()`. Señales: `state_changed`, `health_changed`, `facing_changed`. Estado vía `$StateMachine`; `replicated_state` es la propiedad de red. | §1 (señaliza hacia arriba), §2 (`apply_impulse` es la API; nadie escribe `velocity` ajena), §4 (StateMachine = fuente única), §6 (221) |
| `PlayerKit` | `characters/player/kits/player_kit.gd` (67) | Base de capacidad. **Es un Nodo** (§2 enmendada). `tick(player, intent, delta)`, `on_action_pressed/released`, `on_interrupted`, `is_busy()`, `animation_override()`. Señales: `impulse_requested`, `busy_changed`. No guarda referencia a su Player. | §1, §2 (capacidad = Nodo), §7 |
| `SwordKit` | `characters/player/kits/sword_kit.gd` (100) | Kit ofensivo. Combo encadenable; la ventana activa la abren/cierran pistas de método del `AnimationPlayer` sobre `$Hitbox`. | §2, §13 (AnimationPlayer, no contadores de frames) |
| `ShieldKit` | `characters/player/kits/shield_kit.gd` (104) | Kit defensivo. Guardia sostenida sobre `$GuardBox`; `speed_scale()` la consulta el Player. Parry medido por `Timer`. | §2, §13 (Timer, no contador propio) |
| `Locomotion` | `characters/player/locomotion.gd` (100) | `tick(body, stats, intent, delta, speed_scale) -> bool`, `reset()`. Coyote time, buffer de salto, salto de altura variable. Un solo nodo, no siete motores. | §2 (recibe el body por parámetro), §4 (escritor único de `velocity` en movimiento), §15 |
| `IntentSource` | `characters/player/intent_source.gd` (18) | `poll() -> PlayerIntent`. Base intercambiable: local, red o guion de test. | §8 (único sitio con `Input.*`), §10 (frontera de red) |
| `LocalIntentSource` | `characters/player/local_intent_source.gd` (48) | Lee el InputMap del proyecto según `player_index`. Avisa por `push_error` si falta una acción. | §8, §13 (InputMap del editor, no registro en runtime) |
| `PlayerIntent` | `characters/player/player_intent.gd` (58) | Datos: `move`, `up`, `down`, flancos `*_pressed`, sostenidos `*_held`. `copy_from()`, `clear_edges()`, `facing()`. | §10 |
| `StatsComponent` | `components/stats_component.gd` (134) | `get_stat(id)`, `get_stat_bool/int(id)`, `mark_dirty()`. Descubre hijos `StatModifierNode` solo. Un desbloqueo = un nodo hijo. | §2, §4 (fuente única de stats derivados) |
| `StatModifierNode` | `components/stat_modifier_node.gd` (20) | `get_modifiers() -> Array[StatModifierData]`, señal `modifier_changed`. | §7 |
| `HealthComponent` | `components/health_component.gd` (204) | `take_damage`, `heal`, `heal_full`, `kill`, `revive`, `set_max_health`, `is_invulnerable()`, `get_health_ratio()`. `replicated_health` para la red. **Portado de Tension sin cambios.** | §2, §4, §7 |
| `StateMachine` | `components/state_machine.gd` (133) | `transition_to`, `init_state`, `set_on_enter/exit`, `is_in`, `is_in_any`, `get_state_name`. `replicated_state` para la red. **Portado de Tension sin cambios.** | §4 |
| `AttackData` | `components/combat/attack_data.gd` (36) | `Resource`. Un `.tres` por golpe: animación, daño, empuje, `attack_id`, `max_targets`, `lunge_speed`, `chains`. No dice **cuándo** — eso lo marca la animación. | §13 (datos como Resource) |
| `Attacker` | `components/combat/attacker.gd` (159) | Ejecuta ataques y encadena combos. `attack(facing)`, `interrupt()`, `is_attacking()`, `current_attack()`, y `open_window()`/`close_window()` que llaman las **pistas de método** de la animación. No conoce a su dueño: sirve a jugador, enemigo o trampa. | §2 (pide impulso, no lo aplica), §7, §13 (AnimationPlayer) |
| `DamageReceiver` | `components/combat/damage_receiver.gd` (75) | Convierte impacto en daño: escucha una `Hurtbox`, aplica `DEFENSE`, descuenta salud y pide empuje. `preview_damage(raw)`. Extraído de `Player._on_wounded`, donde solo servía al jugador. | §2 (pide el empuje), §7 |
| `Hitbox` | `components/hitbox.gd` (118) | Área que inflige. `enable()` / `disable()`, `is_active()`, `attacker()`, `direction_to()`. `@export source` identifica al atacante sin exigir `CharacterBody2D` (vale una trampa). Filtra por **contrato** (`covers`/`accepts_hit`), no por clase. | §2 (avisa por API pública), §7, §13 |
| `Hurtbox` | `components/hurtbox.gd` (49) | Área que recibe. `accepts_hit()`, `receive()`, señal `wounded`. Etiqueta `zone` para golpes por zona. | §2, §13 |
| `GuardBox` | `components/guard_box.gd` (92) | Área de guardia. `raise(facing)`, `lower()`, `set_facing()`, `is_in_parry_window()`. `covers()` es **consulta pura** y `register_block()` el efecto — separados para que consultar no emita bloqueos fantasma. | §2, §13 (Timer para el parry) |
| `PlayerCamera` | `systems/camera/player_camera.gd` (66) | `Camera2D` del personaje. `set_local(bool)` la enciende solo en el peer con autoridad; `apply_room_bounds(Rect2)` la encierra en la sala. Adelanto horizontal y suavizado nativos. | §13 (`position_smoothing`, `limit_*`; sin lerp a mano) |
| `Session` | `systems/network/session.gd` (60) | Autoload `SessionState`. `kit_for(peer)`, `kit_scene_for(peer)`, `kit_name_for(peer)`, `assign(host, guest)`, `clear()`. Reparto **determinista por peer_id**: no se replica. | §9 (estado de sesión, `clear()` lo vacía) |
| `Zone` | `level/systems/zone.gd` (103) | `@tool`. Raíz de zona: la **unidad de carga**. `rooms()`, `room(id)`, `doors()`, `door(id)`, `arrival_point(from_door)`. Valida en el editor ids repetidos y spawn inexistente. | §13 (`_get_configuration_warnings`), ADR-001 |
| `RoomBounds` | `level/systems/room_bounds.gd` (99) | `@tool`. Una sala: unidad de diseño y cámara, **no de carga**. `world_rect()`, señal `player_entered`. Al entrar el jugador local llama a `Player.enter_room`. Se dibuja sola en el editor. | §2 (API pública, no escribe la cámara ajena), §13, ADR-001 |
| `ZoneDoor` | `level/systems/zone_door.gd` (126) | `@tool`. Único punto de carga real. `arrival_point()`, señales `traversal_requested`, `waiting_changed`. `required_players = 2` hace imposible que los jugadores queden en zonas distintas. | §13, ADR-001 |
| `RoomScaffold` | `level/systems/room_scaffold.gd` (125) | `@tool`. Geometría **provisional** por banderas de abertura. **A retirar** cuando haya tileset: lo sustituye un `TileMapLayer` con terrain sets. | §13 (provisional, anotado para retirada) |
| `World` | `systems/world/world.gd` (141) | Coordinador. Sostiene la zona activa, hace aparecer los jugadores con `MultiplayerSpawner` y cambia de zona por RPC del host. Una sola zona cargada a la vez. | §1, §3, §13 (`MultiplayerSpawner`), ADR-001 |
| `NetworkManager` | `autoloads/network_manager.gd` (150) | Autoload. `host(port)`, `join(ip, port)`, `leave(reason)`, `reset()`. Señales `game_ready`, `session_ended`, `connection_error`. **No conoce ninguna ruta de escena** — a diferencia del original. | §3, §9 (estado de sesión, se limpia en `reset`) |
| `GameEvents` | `autoloads/game_events.gd` (51) | Autoload. Solo señales, sin estado. Eventos globales: salas, progresión, combate, sesión. Las tres condiciones de admisión están en el propio archivo. | §9 (sin estado) |


### Excepciones vigentes al límite de 400 líneas (§6)

| Archivo | Líneas | Fecha | Condición de salida |
| ------- | ------ | ----- | ------------------- |
| _(ninguna)_ | | | |

---

## Deferred

Patrones y sistemas conscientemente **aplazados**. Cada uno tiene un disparador: mientras
no se cumpla, construirlo es trabajo especulativo y no se hace.

| Patrón / sistema | Disparador de activación |
| ---------------- | ------------------------ |
| Selección de kit en el lobby | Se quiera elegir arma en vez del reparto determinista host = espada |
| Intercambio de kits en caliente | Se decida que espada y escudo son intercambiables a mitad de partida |
| Reconciliación / autoridad del host sobre jugadores | Aparezca competitivo, o se detecten abusos del cliente autoritativo |
| Simulación de enemigos autoritativa en el host | Entren enemigos: su estado no puede ser autoritativo por cliente |
| Geometría con `TileMapLayer` + terrain sets (retira `RoomScaffold`) | Exista un tileset propio |
| Mecanismo de reagrupamiento entre jugadores | Se note en pruebas que la dispersión dentro de una zona molesta (candidato: el tether) |
| Precarga de la zona vecina | Se mida un parón perceptible al cruzar una puerta — no antes |
| Máquina de estados compartida en `components/` | Un segundo tipo de entidad necesita el mismo grafo de estados que el jugador |
| Sistema de guardado | Existe progresión persistente entre sesiones (habilidades desbloqueadas) |

---

## Retired

| Qué | Motivo |
| --- | ------ |
| `systems/world/arena.gd` / `arena.tscn` | Escena de juego de una sola pieza. La sustituye `world.tscn` + zonas al adoptarse el ADR-001. |
| `systems/world/boot.gd` / `boot.tscn` | Andamio de dos jugadores locales sobre una escena fija. Lo sustituye `lobby.tscn` → `arena.tscn` al decidirse que el juego es solo en red. |
| Acciones de entrada `p1_*` / `p2_*` | Colapsadas a un solo juego de acciones: cada cliente controla un personaje, no dos en el mismo teclado. |
