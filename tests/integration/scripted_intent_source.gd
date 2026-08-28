class_name ScriptedIntentSource
extends IntentSource

## Fuente de intent para los tests: el guion se escribe desde fuera.
##
## Sustituye al `LocalIntentSource` antes de que el jugador entre en el árbol,
## así que nada aguas abajo distingue un test de una partida real (§10). Los
## flancos se consumen solos tras un frame, igual que los del teclado.

var _clear_on_next_poll: bool = false


## Un flanco sobrevive exactamente a UN poll y se limpia en el siguiente, igual
## que `Input.is_action_just_pressed`. Limpiarlo en el mismo poll que lo entrega
## haría que el jugador no lo viera nunca.
func poll() -> PlayerIntent:
	if _clear_on_next_poll:
		_intent.clear_edges()
		_clear_on_next_poll = false
		return _intent

	if _intent.jump_pressed or _intent.attack_pressed \
			or _intent.tether_pressed or _intent.interact_pressed:
		_clear_on_next_poll = true
	return _intent


## Fija el eje horizontal sostenido.
func set_move(value: float) -> void:
	_intent.move = clampf(value, -1.0, 1.0)


func set_vertical(up: float, down: float) -> void:
	_intent.up = clampf(up, 0.0, 1.0)
	_intent.down = clampf(down, 0.0, 1.0)


func set_guard(held: bool) -> void:
	_intent.guard_held = held


func set_jump_held(held: bool) -> void:
	_intent.jump_held = held


## Pulsa el salto durante exactamente un frame.
func press_jump() -> void:
	_intent.jump_pressed = true
	_intent.jump_held = true
	_clear_on_next_poll = false


func press_attack() -> void:
	_intent.attack_pressed = true
	_clear_on_next_poll = false


func press_tether() -> void:
	_intent.tether_pressed = true
	_clear_on_next_poll = false


func press_interact() -> void:
	_intent.interact_pressed = true
	_clear_on_next_poll = false


## Suelta todo.
func release_all() -> void:
	_intent.move = 0.0
	_intent.up = 0.0
	_intent.down = 0.0
	_intent.jump_held = false
	_intent.guard_held = false
	_intent.clear_edges()
