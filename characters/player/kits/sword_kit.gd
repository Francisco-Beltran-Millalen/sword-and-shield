class_name SwordKit
extends PlayerKit

## Kit ofensivo. El ataque es una animación, no un contador de frames.
##
## La ventana activa la abren y cierran pistas de método del `AnimationPlayer`
## llamando a `Hitbox.enable()` y `Hitbox.disable()` en los frames exactos
## (§13). Este script no cuenta frames: solo lanza la animación y escucha
## cuándo termina.
##
## Encadenado: si se pulsa de nuevo dentro de la ventana de encadenado, el
## siguiente golpe del combo sale; si no, la cadena se reinicia.

## Nombres de las animaciones del combo, en orden.
@export var combo_animations: Array[StringName] = [&"attack_1", &"attack_2", &"attack_3"]
## Impulso hacia delante al iniciar cada golpe.
@export var lunge_speed: float = 140.0

@onready var hitbox: Hitbox = $Hitbox
@onready var animation: AnimationPlayer = $AnimationPlayer

var _combo_index: int = 0
var _chain_queued: bool = false


func _ready() -> void:
	kit_id = &"sword"
	display_name = "Espada"
	if animation != null and not animation.animation_finished.is_connected(_on_animation_finished):
		animation.animation_finished.connect(_on_animation_finished)


func on_action_pressed(player: Node, intent: PlayerIntent) -> void:
	if is_busy():
		_chain_queued = true
		return
	_start_swing(player, intent)


func tick(_player: Node, _intent: PlayerIntent, _delta: float) -> void:
	pass


func on_interrupted(player: Node) -> void:
	_chain_queued = false
	_combo_index = 0
	if hitbox != null:
		hitbox.disable()
	if animation != null:
		animation.stop()
	super.on_interrupted(player)


func animation_override() -> StringName:
	return _current_animation() if is_busy() else &""


func _start_swing(player: Node, intent: PlayerIntent) -> void:
	_set_busy(true)
	_chain_queued = false

	var facing: int = intent.facing()
	if facing == 0 and player.has_method("get_facing"):
		facing = player.get_facing()
	if facing == 0:
		facing = 1
	scale.x = float(facing)

	if lunge_speed > 0.0:
		impulse_requested.emit(Vector2(float(facing) * lunge_speed, 0.0))

	var anim := _current_animation()
	if animation != null and animation.has_animation(anim):
		animation.play(anim)
	else:
		# Sin animación todavía (arte pendiente): el kit no se queda colgado.
		push_warning("SwordKit: falta la animación '%s'; se resuelve al instante." % anim)
		_finish_swing()


func _current_animation() -> StringName:
	if combo_animations.is_empty():
		return &"attack_1"
	return combo_animations[_combo_index % combo_animations.size()]


func _on_animation_finished(_anim_name: StringName) -> void:
	_finish_swing()


func _finish_swing() -> void:
	if hitbox != null:
		hitbox.disable()
	if _chain_queued:
		_combo_index += 1
		_chain_queued = false
		_set_busy(false)
		return
	_combo_index = 0
	_set_busy(false)
