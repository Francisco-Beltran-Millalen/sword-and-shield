class_name Locomotion
extends Node

## Movimiento de plataformas: un solo nodo para todos los estados.
##
## El proyecto anterior repartía esto entre siete "motores" (suelo, aire, pared,
## colgado, apuntando, columpio, K.O.) porque cada forma reclamaba escribir
## `velocity` y hubo que arbitrar quién mandaba cada frame. Con capacidades como
## nodos ese arbitraje desaparece: la locomoción siempre manda sobre el
## movimiento, y los kits piden impulsos que el Player suma (§2, §4).
##
## No guarda referencia a su Player: lo recibe en cada llamada (§15).

## Margen tras salir de una plataforma en el que el salto todavía cuenta.
@export var coyote_time: float = 0.10
## Margen antes de tocar suelo en el que un salto pulsado se recuerda.
@export var jump_buffer: float = 0.12
## Al soltar el salto en ascenso, la velocidad vertical se recorta por esto.
@export_range(0.0, 1.0, 0.05) var jump_cut: float = 0.45

var _coyote: float = 0.0
var _buffer: float = 0.0
var _air_jumps_left: int = 0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1400.0)


## Aplica el movimiento de este frame. Devuelve `true` si se saltó, para que
## quien llame pueda reaccionar (animación, sonido).
func tick(body: CharacterBody2D, stats: StatsComponent, intent: PlayerIntent,
		delta: float, speed_scale: float = 1.0) -> bool:
	var on_floor := body.is_on_floor()
	_tick_timers(delta, on_floor, intent, stats)

	_apply_horizontal(body, stats, intent, delta, speed_scale)
	_apply_gravity(body, stats, intent, delta, on_floor)

	var jumped := _try_jump(body, stats, on_floor)
	body.move_and_slide()
	return jumped


func reset() -> void:
	_coyote = 0.0
	_buffer = 0.0
	_air_jumps_left = 0


func _tick_timers(delta: float, on_floor: bool, intent: PlayerIntent, stats: StatsComponent) -> void:
	if on_floor:
		_coyote = coyote_time
		_air_jumps_left = stats.get_stat_int(StatsComponent.StatID.AIR_JUMPS)
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	_buffer = maxf(_buffer - delta, 0.0)
	if intent.jump_pressed:
		_buffer = jump_buffer


func _apply_horizontal(body: CharacterBody2D, stats: StatsComponent,
		intent: PlayerIntent, delta: float, speed_scale: float) -> void:
	var max_speed := stats.get_stat(StatsComponent.StatID.MAX_SPEED) * speed_scale
	var accel := stats.get_stat(StatsComponent.StatID.ACCELERATION)
	var friction := stats.get_stat(StatsComponent.StatID.FRICTION)

	if not body.is_on_floor():
		accel *= stats.get_stat(StatsComponent.StatID.AIR_CONTROL)
		friction *= stats.get_stat(StatsComponent.StatID.AIR_CONTROL)

	var target := intent.move * max_speed
	var rate := accel if absf(intent.move) > 0.01 else friction
	body.velocity.x = move_toward(body.velocity.x, target, rate * delta)


func _apply_gravity(body: CharacterBody2D, stats: StatsComponent,
		intent: PlayerIntent, delta: float, on_floor: bool) -> void:
	if on_floor:
		return
	body.velocity.y += _gravity * stats.get_stat(StatsComponent.StatID.GRAVITY_SCALE) * delta
	# Salto de altura variable: soltar el botón en ascenso recorta el impulso.
	if body.velocity.y < 0.0 and not intent.jump_held:
		body.velocity.y *= 1.0 - jump_cut * (delta * 60.0)


func _try_jump(body: CharacterBody2D, stats: StatsComponent, on_floor: bool) -> bool:
	if _buffer <= 0.0:
		return false

	var can_ground_jump := on_floor or _coyote > 0.0
	if not can_ground_jump and _air_jumps_left <= 0:
		return false

	if not can_ground_jump:
		_air_jumps_left -= 1

	body.velocity.y = stats.get_stat(StatsComponent.StatID.JUMP_VELOCITY)
	_buffer = 0.0
	_coyote = 0.0
	return true
