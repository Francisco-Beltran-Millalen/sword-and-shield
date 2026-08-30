extends Node

## Bus de eventos verdaderamente globales.
##
## Existe para un problema concreto del proyecto anterior: allí `main.gd`
## cableaba el juego entero en `_ready()` con ~40 líneas de `.connect()` y
## lambdas, más referencias directas a `$Player1`, `$Tether`, `$Enemy`. Funciona
## con una escena fija; un metroidvania tiene decenas de salas que entran y salen
## del árbol, y ese cableado habría que rehacerlo en cada transición.
##
## REGLA DE USO (§1 de la constitución): esto NO es un atajo para saltarse el
## árbol de escenas. Un evento entra aquí solo si cumple las tres condiciones:
##
##   1. Su emisor y su receptor no se conocen ni pueden conocerse por el árbol.
##   2. Sobrevive a las transiciones de sala.
##   3. Puede tener cero receptores sin que nada se rompa.
##
## Todo lo demás —un jugador avisando a su HUD, un enemigo a su spawner— viaja
## por señales normales, llamando hacia abajo y señalizando hacia arriba (§1).
##
## Este autoload no guarda estado (§9): solo retransmite. El estado del mundo
## vive en el recurso de progreso, no aquí.

## --- Zonas y salas ---
## Se pidió cambiar de zona. `door_id` es la puerta por la que se aparece.
@warning_ignore("unused_signal")
signal zone_change_requested(zone_path: String, door_id: StringName)
## Un jugador local entró en una sala nueva. La sala NO se carga: es una región
## dentro de la zona, y esto solo significa que cambió el encuadre.
@warning_ignore("unused_signal")
signal room_entered(room_id: StringName)
## Terminó de cargar una zona y los jugadores ya están colocados. La zona es la
## unidad de carga; esto sí es un evento de carga real.
@warning_ignore("unused_signal")
signal zone_entered(zone_id: StringName)

## --- Progresión ---
## Se adquirió una habilidad. El HUD, las puertas y el mapa reaccionan.
@warning_ignore("unused_signal")
signal ability_unlocked(ability_id: StringName)
## Se activó un punto de guardado.
@warning_ignore("unused_signal")
signal checkpoint_reached(checkpoint_id: StringName)

## --- Combate ---
## Un golpe conectó. Lo consumen los efectos de pantalla, el audio y el hit-stop.
@warning_ignore("unused_signal")
signal hit_landed(attacker: Node, target: Node, damage: int)
## Un escudo bloqueó un golpe (parry incluido, distinguible por `perfect`).
@warning_ignore("unused_signal")
signal hit_guarded(guard: Node, attacker: Node, perfect: bool)
