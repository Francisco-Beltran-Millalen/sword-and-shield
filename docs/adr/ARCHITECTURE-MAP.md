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
| `Player` | `characters/player/player.gd` (311) | Entidad. `equip_kit(scene)`, `apply_impulse(v)` — **única** vía para que algo externo lo mueva, `place_at(point)`, `revive_full()`, `get_facing()`. Señales: `state_changed`, `health_changed`, `facing_changed`, `room_changed`. Estado vía `$StateMachine`; `replicated_state` es la propiedad de red. | §1 (señaliza hacia arriba), §2 (`apply_impulse` es la API; nadie escribe `velocity` ajena), §4 (StateMachine = fuente única), §6 |
| `PlayerKit` | `characters/player/kits/player_kit.gd` (69) | Base de capacidad. **Es un Nodo** (§2 enmendada). `tick(player, intent, delta)`, `on_action_pressed`, `on_interrupted`, `is_busy()`, `animation_override()`, `speed_scale()`. Señales: `impulse_requested`, `busy_changed`. No guarda referencia a su Player. | §1, §2 (capacidad = Nodo), §7 |
| `SwordKit` | `characters/player/kits/sword_kit.gd` (77) | Kit ofensivo. Combo encadenable; la ventana activa la abren/cierran pistas de método del `AnimationPlayer` sobre `$Hitbox`. | §2, §13 (AnimationPlayer, no contadores de frames) |
| `ShieldKit` | `characters/player/kits/shield_kit.gd` (104) | Kit defensivo. Guardia sostenida sobre `$GuardBox`; `speed_scale()` la consulta el Player. Parry medido por `Timer`. | §2, §13 (Timer, no contador propio) |
| `Locomotion` | `characters/player/locomotion.gd` (100) | `tick(body, stats, intent, delta, speed_scale) -> bool`, `reset()`. Coyote time, buffer de salto, salto de altura variable. Un solo nodo, no siete motores. | §2 (recibe el body por parámetro), §4 (escritor único de `velocity` en movimiento), §15 |
| `IntentSource` | `characters/player/intent_source.gd` (18) | `poll() -> PlayerIntent`. Base intercambiable: local, red o guion de test. | §8 (único sitio con `Input.*`), §10 (frontera de red) |
| `LocalIntentSource` | `characters/player/local_intent_source.gd` (43) | Lee el InputMap del proyecto según `player_index`. Avisa por `push_error` si falta una acción. | §8, §13 (InputMap del editor, no registro en runtime) |
| `PlayerIntent` | `characters/player/player_intent.gd` (58) | Datos: `move`, `up`, `down`, flancos `*_pressed`, sostenidos `*_held`. `copy_from()`, `clear_edges()`, `facing()`. | §10 |
| `StatsComponent` | `components/stats_component.gd` (134) | `get_stat(id)`, `get_stat_bool/int(id)`, `mark_dirty()`. Descubre hijos `StatModifierNode` solo. Un desbloqueo = un nodo hijo. | §2, §4 (fuente única de stats derivados) |
| `StatModifierNode` | `components/stat_modifier_node.gd` (20) | `get_modifiers() -> Array[StatModifierData]`, señal `modifier_changed`. | §7 |
| `StatModifierData` | `components/stat_modifier_data.gd` (11) | `RefCounted` de datos: `stat_id`, `add_value`, `mult_value`. Lo que un `StatModifierNode` aporta. | §4 |
| `HealthComponent` | `components/health_component.gd` (204) | `take_damage`, `heal`, `heal_full`, `kill`, `revive`, `set_max_health`, `is_invulnerable()`, `get_health_ratio()`. `replicated_health` para la red. **Portado de Tension sin cambios.** | §2, §4, §7 |
| `StateMachine` | `components/state_machine.gd` (133) | `transition_to`, `init_state`, `set_on_enter/exit`, `is_in`, `is_in_any`, `get_state_name`. `replicated_state` para la red. **Portado de Tension sin cambios.** | §4 |
| `AttackData` | `components/combat/attack_data.gd` (36) | `Resource`. Un `.tres` por golpe: animación, daño, empuje, `attack_id`, `max_targets`, `lunge_speed`, `chains`. No dice **cuándo** — eso lo marca la animación. | §13 (datos como Resource) |
| `Attacker` | `components/combat/attacker.gd` (191) | Ejecuta ataques y encadena combos. `attack(facing)`, `interrupt()`, `is_attacking()`, `current_attack()`, y `open_window()`/`close_window()` que llaman las **pistas de método** de la animación. Recuerda el `facing` para los golpes encadenados. Encuentra su `AnimationPlayer` y su `Hitbox` por nombre entre hermanos o por tipo bajo la entidad, así que no exige una estructura de escena concreta. No conoce a su dueño: sirve a jugador, enemigo o trampa. | §2 (pide impulso, no lo aplica), §7, §13 (AnimationPlayer) |
| `DamageReceiver` | `components/combat/damage_receiver.gd` (146) | Convierte impacto en daño: escucha una `Hurtbox`, aplica `DEFENSE`, descuenta salud y pide empuje. `preview_damage(raw)`. En red **encamina** el golpe al peer con autoridad sobre la víctima: quien lo detecta no siempre es quien puede aplicarlo; si ese peer ya no está en la sesión, el golpe se descarta en vez de intentar un `rpc_id` imposible. Extraído de `Player._on_wounded`, donde solo servía al jugador. | §2 (pide el empuje), §7 |
| `Hitbox` | `components/hitbox.gd` (153) | Área que inflige. `enable()` / `disable()`, `is_active()`, `attacker()`, `direction_to()`. `@export source` identifica al atacante sin exigir `CharacterBody2D` (vale una trampa). Filtra por **contrato** (`covers`/`accepts_hit`), no por clase. La ventana viaja en una bandera propia y `monitoring` la sigue en diferido: Godot rechaza escribirlo mientras despacha señales de área, que es justo desde donde llega `disable()`. | §2 (avisa por API pública), §7, §13 |
| `Hurtbox` | `components/hurtbox.gd` (64) | Área que recibe. `accepts_hit()`, `receive()`, `entity()`, señal `wounded`. Etiqueta `zone` para golpes por zona. | §2, §13 |
| `GuardBox` | `components/guard_box.gd` (100) | Área de guardia. `raise(facing)`, `lower()`, `set_facing()`, `is_raised()`, `is_in_parry_window()`. `covers()` es **consulta pura** y `register_block()` el efecto — separados para que consultar no emita bloqueos fantasma. Guardia alta como bandera propia, `monitorable` en diferido (mismo motivo que `Hitbox`). | §2, §13 (Timer para el parry) |
| `Enemy` | `characters/enemy/enemy.gd` (255) | Entidad. `apply_impulse(v)`, `place_at(p)`, `revive_full()`, `get_facing()`, `archetype`. Señales: `state_changed`, `health_changed`. **No estrena ningún sistema**: reutiliza `Locomotion`, `Attacker`, `Hitbox`, `Hurtbox`, `DamageReceiver`, stats y salud del jugador. Lo simula el host; sin autoridad hace `return`. | §1, §2 (reparte el arquetipo entre sus hijos), §4, §6, §7 |
| `EnemyArchetype` | `characters/enemy/enemy_archetype.gd` (59) | `Resource`. Fuente de verdad de los números de un enemigo: cuerpo, aguante, movimiento, vista, ataques. Un enemigo nuevo es un `.tres`. | §4 (un dueño por hecho), §13 |
| `AIIntentSource` | `characters/enemy/ai_intent_source.gd` (115) | `extends IntentSource`. `configure(archetype, anchor)`, `decide(body, eyes, delta)`, `mode`. Rellena el MISMO intent que el teclado, así que aguas abajo nadie distingue enemigo de jugador. Sustituible por nodo: los tests conducen enemigos con `ScriptedIntentSource`. | §8, §10 (frontera de intención) |
| `Perception` | `characters/enemy/perception.gd` (88) | `Area2D`. `has_targets()`, `closest_to(origin)`, señales `target_entered`/`target_exited`. Filtra por capa, no por tipo: a quién ve se cambia en el inspector. | §7, §13 (`Area2D`, no raycasts a mano) |
| `PlayerCamera` | `systems/camera/player_camera.gd` (80) | `Camera2D` del personaje. `set_local(bool)` la enciende solo en el peer con autoridad; `apply_room_bounds(Rect2)` la encierra en la sala. Adelanto horizontal y suavizado nativos. | §13 (`position_smoothing`, `limit_*`; sin lerp a mano) |
| `Session` | `systems/network/session.gd` (59) | Autoload `SessionState`. `kit_for(peer)`, `kit_scene_for(peer)`, `kit_name_for(peer)`, `assign(host, guest)`, `clear()`. Reparto **determinista por peer_id**: no se replica. | §9 (estado de sesión, `clear()` lo vacía) |
| `lobby.gd` | `systems/network/lobby.gd` (96) | Pantalla previa (script de escena, sin `class_name`). Única, junto al `World`, que puede llamar a `NetworkManager.host()`/`.join()`. Atajos `--host` / `--join <ip>`. Escucha `session_ended`: una sesión que muere antes de entrar en la partida devuelve el lobby en vez de dejarlo en "Conectando…" para siempre. | §3 |
| `Zone` | `level/systems/zone.gd` (103) | `@tool`. Raíz de zona: la **unidad de carga**. `rooms()`, `room(id)`, `doors()`, `door(id)`, `arrival_point(from_door)`. Valida en el editor ids repetidos y spawn inexistente. | §13 (`_get_configuration_warnings`), ADR-001 |
| `RoomBounds` | `level/systems/room_bounds.gd` (103) | `@tool`. Una sala: unidad de diseño y cámara, **no de carga**. `world_rect()`, señal `occupant_entered`. Al entrar el jugador local llama a `Player.enter_room`. Se dibuja sola en el editor. | §2 (API pública, no escribe la cámara ajena), §13, ADR-001 |
| `ZoneDoor` | `level/systems/zone_door.gd` (174) | `@tool`. Único punto de carga real. `arrival_point()`, `travellers_inside()`, `receive_arrival()`, señales `traversal_requested`, `waiting_changed`. `required_players = 2` hace imposible que los jugadores queden en zonas distintas. Cuenta a los presentes con `get_overlapping_bodies()` en vez de llevar la cuenta a mano (§13), y no viaja por quien fue **dejado** aquí al llegar: sin eso el viaje rebotaba sin fin entre dos zonas. | §5 (el `World` le empuja la llegada), §13 (`Area2D` como fuente del conteo), ADR-001 |
| `RoomScaffold` | `level/systems/room_scaffold.gd` (192) | `@tool`. Geometría **provisional** por banderas de abertura. `floor_surface_y()`, `ceiling_surface_y()`. Toda medida de paso sale del alcance medido del jugador, y valida en el editor. **A retirar** cuando haya tileset: lo sustituye un `TileMapLayer` con terrain sets. | §13 (provisional, anotado para retirada) |
| `world.gd` | `systems/world/world.gd` (263) | Coordinador (script de escena, sin `class_name`). Sostiene la zona activa, hace aparecer los jugadores con `MultiplayerSpawner` y cambia de zona por RPC del host. Una sola zona cargada a la vez. Es también quien alimenta el `Hud`: engancha la salud de cada jugador **antes** de meterlo en el árbol y reparte las ranuras por `peer_id`. Coloca únicamente a los jugadores sobre los que este peer manda (§3): mover un cuerpo ajeno lo devuelve su dueño en el paquete siguiente, y ese vaivén lo leía la puerta como un cruce. La carga de zona va **diferida siempre** (`_perform_zone_change.call_deferred`): la pide el `body_entered` de una puerta y cambiar el árbol de colisiones dentro del flush de física está prohibido. | §1, §3, §5 (empuja el contexto al HUD), §13 (`MultiplayerSpawner`), ADR-001 |
| `Hud` | `ui/hud/hud.gd` (73) | Capa UI, **solo lectura**. `set_health(current, maximum, slot)`, `set_slot_label(text, slot)`, `clear_slot(slot)`, `set_door_wait(present, required)`. No conoce a ninguna entidad, no busca a nadie y no se suscribe a nada: recibe enteros del `World` y los pinta, así que un jugador que se va o una zona que se descarga no le dejan punteros muertos. | §1, §5 (el contexto se empuja), §13 (`ProgressBar` y `Label` nativos) |
| `NetworkManager` | `autoloads/network_manager.gd` (267) | Autoload. `host(port)`, `join(ip, port)`, `leave(reason)`, `reset()`, `report_scene_ready()`. Señales `game_ready`, `session_ended`, `connection_error`, `all_peers_ready`. **No conoce ninguna ruta de escena** — a diferencia del original. El acuse de carga vive aquí y no en el `World` porque un autoload existe en ambos extremos aunque el `World` del otro todavía no, que es justo el caso que ordena; se rinde con aviso a los 15 s en vez de esperar callado. `reset()` mantiene la invariante de que **siempre hay un peer asignado**, restaurando el `OfflineMultiplayerPeer` de arranque: sin ella, preguntar por la autoridad entre el cierre y el cambio de escena es un error de motor. | §3 (`report_scene_ready` es solo-coordinador), §9 (estado de sesión etiquetado, se limpia en `reset`) |
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
| Validación del daño encaminado entre peers | Aparezca competitivo. Hoy `DamageReceiver` encamina el golpe al dueño de la víctima y este se fía: en cooperativo contra el entorno basta |
| Geometría con `TileMapLayer` + terrain sets (retira `RoomScaffold`) | Exista un tileset propio |
| Mecanismo de reagrupamiento entre jugadores | Se note en pruebas que la dispersión dentro de una zona molesta (candidato: el tether) |
| Precarga de la zona vecina | Se mida un parón perceptible al cruzar una puerta — no antes |
| Máquina de estados compartida en `components/` | Un segundo tipo de entidad necesita el mismo grafo de estados que el jugador |
| Sistema de guardado | Existe progresión persistente entre sesiones (habilidades desbloqueadas) |
| `DAMAGE_POWER` y `KNOCKBACK_DEALT` (declarados en `StatsComponent`, sin lector) | Se quiera escalar el golpe por quien lo asesta. Van en el `Attacker`, no en la entidad |
| `INVULN_SECONDS` (declarado, sin lector) | Una habilidad o un objeto necesite alargar los i-frames. Hoy `HealthComponent.invulnerability_seconds` es su propio `@export` y nadie los enlaza |
| `MASS` (declarado, sin lector) | El empuje deba depender de la corpulencia del que lo encaja |
| `tether_pressed` e `interact_pressed` (viajan en el intent, sin consumidor) | Existan el salto largo y los objetos interactuables |
| Acuse de carga también en el cambio de zona (hoy solo en el arranque) | Se mida pérdida de estado real al cruzar, no el ruido de consola que ya se recupera solo. Medido con el cliente cargando 0,6 s tarde: seis líneas de "Node not found" de los sincronizadores de enemigos y nada más — no hay spawn que perder, porque cada peer instancia la zona localmente. Bloquear cada viaje hasta el acuse costaba un RTT y podía dejar enemigos mudos para siempre si el acuse fallaba |
| Identificador de ronda en el acuse (`_peers_ready`) | Se admita reconexión: hoy `_game_started` es un pestillo que solo limpia `reset()`, y `reset()` cierra el socket, así que no hay reconexión posible |
| Limpiar `_peers_ready` cuando un peer se cae a media ronda | Se note la espera. Hoy el acuse de quien se desconectó se queda en el conjunto y la ronda no se cierra hasta el timeout de 15 s; el camino habitual es que `session_ended` se adelante y saque a todos al lobby antes, así que no se ha visto |
| Punto de reaparición propio | Existan puntos de guardado. Hoy `World._on_entity_downed` espera 1,5 s y revive en `current_zone`, que puede ser OTRA si mientras tanto se cruzó una puerta: el caído reaparece en la zona nueva, no donde cayó |
| Devolver la autoridad a los personajes al cerrar la sesión | Molesten los 1-2 frames en que el ex-cliente no simula su propio cuerpo. Al restaurar el peer offline, `get_unique_id()` vuelve a 1 y su `Player` —autoridad = su antiguo `peer_id`— deja de simular hasta que el cambio de escena al lobby se lo lleva. Es congelarse, no romperse |

---

## Retired

| Qué | Motivo |
| --- | ------ |
| `systems/world/arena.gd` / `arena.tscn` | Escena de juego de una sola pieza. La sustituye `world.tscn` + zonas al adoptarse el ADR-001. |
| `systems/world/boot.gd` / `boot.tscn` | Andamio de dos jugadores locales sobre una escena fija. Lo sustituye `lobby.tscn` → `arena.tscn` al decidirse que el juego es solo en red. |
| `Enemy` de Tension (459 líneas) y su `LocomotionStrategy` | No se portó: superaba el tope de §6 desde el primer commit y mantenía `Array[Player]`; su locomoción era un `Resource` con lógica, que es lo que §2 prohíbe tras la auditoría. Se rehízo sobre los componentes que ya existían. |
| Acciones de entrada `p1_*` / `p2_*` | Colapsadas a un solo juego de acciones: cada cliente controla un personaje, no dos en el mismo teclado. |
