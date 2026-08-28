class_name PlayerKit
extends Node2D

## El equipo fijo de un jugador: espada o escudo.
##
## ES UN NODO, y eso es deliberado. En el proyecto anterior las capacidades eran
## `RefCounted`, así que no podían tener hijos, ni `_physics_process`, ni
## `@export`, ni escribir `velocity`. De ahí salió una cola de banderas
## (`pending_dash`, `pending_anchor_stop`…) en un componente compartido y diez
## variables de estado por capacidad dentro del god-object `Player`.
##
## Siendo un nodo, un kit cuelga de sí mismo su hitbox, su guardia, su
## `AnimationPlayer` y sus timers, y se apaga entero con
## `set_physics_process(false)`. Ver §2 en la constitución.
##
## El kit NO guarda una referencia a su Player: lo recibe como parámetro en cada
## llamada (§1, §15). El Player llama hacia abajo; el kit señaliza hacia arriba.

## El kit quiere mover al jugador (arremetida, retroceso de guardia). El Player
## decide si lo aplica — el kit nunca escribe `velocity` ajena (§2).
@warning_ignore("unused_signal")
signal impulse_requested(impulse: Vector2)
## El kit entró o salió de una acción que bloquea el control normal.
signal busy_changed(busy: bool)

@export var kit_id: StringName = &"base"
@export var display_name: String = "Base"

var _busy: bool = false


## ¿El kit está en medio de una acción que se adueña del control?
func is_busy() -> bool:
	return _busy


## Lo llama el Player en cada frame de física, antes de mover.
func tick(_player: Node, _intent: PlayerIntent, _delta: float) -> void:
	pass


## Se pulsó el botón de acción principal (atacar / levantar guardia).
func on_action_pressed(_player: Node, _intent: PlayerIntent) -> void:
	pass


## El jugador recibió daño; el kit cancela lo que estuviera haciendo.
func on_interrupted(_player: Node) -> void:
	_set_busy(false)


## Nombre del estado de animación que el kit quiere imponer, o `&""` si no
## impone ninguno y manda la locomoción.
func animation_override() -> StringName:
	return &""


## Multiplicador de velocidad que impone el kit (guardia alta, arma pesada).
## Está aquí, y no como duck typing en el anfitrión, para que el contrato del
## kit se lea entero en un solo archivo.
func speed_scale() -> float:
	return 1.0


func _set_busy(value: bool) -> void:
	if _busy == value:
		return
	_busy = value
	busy_changed.emit(_busy)
