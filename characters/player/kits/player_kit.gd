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
## llamada (§1). El Player llama hacia abajo; el kit señaliza hacia arriba.

## El kit quiere mover al jugador (arremetida, retroceso de guardia). El Player
## decide si lo aplica — el kit nunca escribe `velocity` ajena (§2).
@warning_ignore("unused_signal")
signal impulse_requested(impulse: Vector2)
## El kit entró o salió de una acción que bloquea el control normal.
signal busy_changed(busy: bool)
## Qué debería estar haciendo el CUERPO de quien empuña. Vacío = que mande el
## estado. Está aquí, junto a `is_busy()` y `speed_scale()`, porque el contrato
## del kit se lee entero en un solo archivo.
##
## Existe porque el estado no basta: `Player.State.KIT_ACTION` es uno solo para
## atacar y para guardar, y el combo son tres golpes bajo él. El kit es el único
## que sabe cuál de las dos cosas está pasando, y lo dice hacia arriba (§1) sin
## conocer a quien anima.
signal pose_changed(pose: StringName)

@export var kit_id: StringName = &"base"
@export var display_name: String = "Base"

var _busy: bool = false
var _pose: StringName = &""


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
	_set_pose(&"")


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


## Anuncia la pose del cuerpo. A diferencia de `_set_busy`, repetir la MISMA
## pose sí emite: el segundo golpe de un combo no cambia de estado ni de pose, y
## quien anima necesita el aviso para rearrancar el gesto.
func _set_pose(value: StringName) -> void:
	if value == &"" and _pose == &"":
		return
	_pose = value
	pose_changed.emit(_pose)
