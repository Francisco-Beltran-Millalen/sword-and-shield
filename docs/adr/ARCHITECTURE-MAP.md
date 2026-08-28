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
| `Hitbox` | `components/hitbox.gd` (100) | Área que inflige. `enable()` / `disable()` desde pistas de método; `is_active()`, `attacker()`, `direction_to(target)`. Señales `hit`, `guarded`. Nace apagada. | §2 (emite, no aplica daño), §13 (Area2D) |
| `Hurtbox` | `components/hurtbox.gd` (49) | Área que recibe. `accepts_hit()`, `receive()`, señal `wounded`. Etiqueta `zone` para golpes por zona. | §2, §13 |
| `GuardBox` | `components/guard_box.gd` (86) | Área de guardia. `raise(facing)`, `lower()`, `set_facing()`, `is_in_parry_window()`, `blocks(hitbox)`. Señal `blocked(hitbox, perfect)`. | §2, §13 (Timer para el parry) |
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
| Replicación en red (`MultiplayerSpawner`, §3, §10) | Se resuelve la decisión pendiente de cooperativo a favor de red |
| Plataforma de cámara definitiva (`systems/camera/`) | Se elige modelo de cámara (compartida / split-screen / salas independientes) |
| Intercambio de kits en caliente | Se decide que espada y escudo son intercambiables en partida |
| Máquina de estados compartida en `components/` | Un segundo tipo de entidad necesita el mismo grafo de estados que el jugador |
| Sistema de guardado | Existe progresión persistente entre sesiones (habilidades desbloqueadas) |

---

## Retired

Decisiones y componentes retirados, con el motivo. Vacío por ahora.
