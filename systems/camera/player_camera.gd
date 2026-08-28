class_name PlayerCamera
extends Camera2D

## Cámara del personaje. Cada cliente enmarca al suyo.
##
## Va colgada del `Player` y se enciende únicamente en el peer que tiene
## autoridad sobre él: los personajes remotos llevan su cámara apagada. Así no
## hace falta ningún gestor de cámaras — el motor ya usa la `Camera2D` activa
## del viewport, y solo hay una activa por cliente (§13).
##
## Que cada cliente enmarque a su propio personaje es lo que permite que los dos
## jugadores estén en salas distintas sin conflicto de encuadre. Es el requisito
## que hace viable la exploración divergente de un metroidvania cooperativo.
##
## El suavizado y los límites son propiedades nativas de `Camera2D`; no hay
## `lerp` a mano en `_process` como en el proyecto anterior.

## Desplazamiento vertical del encuadre: mirar algo por encima del personaje.
@export var look_ahead_y: float = -48.0
## Píxeles que la cámara se adelanta en la dirección de avance.
@export var look_ahead_x: float = 40.0
## Suavidad del adelanto horizontal (mayor = más rápido).
@export var look_ahead_speed: float = 3.0
## A quién sigue. Vacío = el padre, que es el caso normal (la cámara cuelga de
## su personaje). Explicitarlo permite encuadrar otra cosa —una cinemática, un
## jefe— sin reparentar la cámara.
@export var target: Node2D

var _look_offset_x: float = 0.0


func _ready() -> void:
	if target == null:
		target = get_parent() as Node2D
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	ignore_rotation = true


## La llama el `Player` al resolver su autoridad. Solo la cámara del personaje
## local queda activa; el motor usa la `Camera2D` con `enabled` del viewport.
func set_local(is_local: bool) -> void:
	enabled = is_local
	if is_local:
		make_current()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if target == null:
		return
	# El adelanto necesita saber hacia dónde va el objetivo. Se toma de
	# `velocity` si la tiene (cualquier cuerpo la expone); si no, no se adelanta.
	var speed_x := 0.0
	var velocity_value: Variant = target.get(&"velocity")
	if velocity_value is Vector2:
		speed_x = (velocity_value as Vector2).x

	var target_x := 0.0
	if absf(speed_x) > 20.0:
		target_x = signf(speed_x) * look_ahead_x
	_look_offset_x = move_toward(_look_offset_x, target_x, look_ahead_speed * look_ahead_x * delta)

	offset = Vector2(_look_offset_x, look_ahead_y)


## Encierra la cámara dentro del rectángulo de una sala. Lo llamará el sistema
## de salas al entrar; `Rect2()` vacío suelta los límites.
func apply_room_bounds(bounds: Rect2) -> void:
	if bounds.size == Vector2.ZERO:
		limit_left = -10000000
		limit_top = -10000000
		limit_right = 10000000
		limit_bottom = 10000000
		return
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
