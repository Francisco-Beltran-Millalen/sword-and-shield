class_name GuardBox
extends Area2D

## Volumen de GUARDIA: intercepta golpes antes de que lleguen a la hurtbox.
##
## Es la mitad defensiva del kit asimétrico. Un golpe que entra aquí no daña;
## según el momento en que se levantó la guardia se resuelve como bloqueo
## normal o como parry.
##
## La ventana de parry se mide con un `Timer` del motor, no con un contador de
## frames propio (§13). Se arranca al entrar en guardia y, mientras corre,
## cualquier impacto es perfecto.

## Bloqueó un golpe. `perfect` distingue el parry del bloqueo normal.
signal blocked(hitbox: Hitbox, perfect: bool)

## Segundos desde que se levanta la guardia durante los cuales un golpe es parry.
@export var parry_window: float = 0.18
## Arco frontal que cubre la guardia, en grados. 180 = todo el frente.
@export_range(0.0, 360.0, 5.0) var coverage_degrees: float = 180.0
## Fracción del empuje que atraviesa un bloqueo normal (el parry no empuja).
@export_range(0.0, 1.0, 0.05) var blocked_knockback_ratio: float = 0.35

var _facing: int = 1
var _parry_timer: Timer


func _ready() -> void:
	monitoring = false   ## No busca: la encuentran las hitboxes.
	monitorable = true
	set_deferred("monitorable", false)   ## Arranca bajada.

	_parry_timer = Timer.new()
	_parry_timer.one_shot = true
	_parry_timer.wait_time = parry_window
	add_child(_parry_timer)


## Levanta la guardia y abre la ventana de parry.
func raise(facing: int) -> void:
	_facing = signi(facing) if facing != 0 else 1
	monitorable = true
	_parry_timer.start(parry_window)


## Actualiza hacia dónde mira la guardia SIN reabrir la ventana de parry.
## Girarse mientras se bloquea no debe regalar parrys.
func set_facing(facing: int) -> void:
	if facing != 0:
		_facing = signi(facing)


## Baja la guardia.
func lower() -> void:
	monitorable = false
	_parry_timer.stop()


func is_raised() -> bool:
	return monitorable


func is_in_parry_window() -> bool:
	return monitorable and not _parry_timer.is_stopped()


## ¿Este golpe queda cubierto? **Consulta pura, sin efectos.** Se separó de
## `register_block` porque emitir la señal desde la pregunta producía bloqueos
## fantasma en cuanto dos hitboxes consultaban la misma guardia en un frame, o
## alguien quería previsualizar sin aplicar.
func covers(hitbox: Node) -> bool:
	if not monitorable:
		return false
	var point: Vector2 = hitbox.global_position if hitbox is Node2D else global_position
	return _covers(point)


## Registra el bloqueo y avisa. La llama la hitbox tras confirmar con `covers`.
func register_block(hitbox: Node) -> void:
	blocked.emit(hitbox, is_in_parry_window())


func _covers(from_position: Vector2) -> bool:
	if coverage_degrees >= 360.0:
		return true
	var to_attacker := from_position - global_position
	if to_attacker.length_squared() < 0.0001:
		return true
	var facing_vector := Vector2(float(_facing), 0.0)
	var angle := rad_to_deg(absf(facing_vector.angle_to(to_attacker.normalized())))
	return angle <= coverage_degrees * 0.5
