class_name AIIntentSource
extends IntentSource

## Lo único que un enemigo tiene y un jugador no: decidir por su cuenta.
##
## Produce exactamente el mismo `PlayerIntent` que produce el teclado, así que
## `Locomotion` y el resto de la cadena no distinguen un enemigo de un jugador
## (§10). Ese es todo el truco del enemigo: no estrena movimiento ni combate,
## solo cambia de dónde salen las intenciones.
##
## Y por eso los tests pueden conducir un enemigo con un `ScriptedIntentSource`
## igual que conducen un jugador: basta sustituir este nodo.
##
## No guarda referencia a su enemigo: recibe el cuerpo y la vista por parámetro
## en cada `decide()` (§1).

enum Mode {
	PATROL,   ## Ronda alrededor de donde apareció.
	CHASE,    ## Va a por alguien que ve.
	RETURN,   ## Vuelve a su sitio tras perderlo.
}

var mode: Mode = Mode.PATROL

var _archetype: EnemyArchetype
var _anchor: Vector2 = Vector2.ZERO
var _patrol_direction: float = 1.0
var _attack_cooldown_left: float = 0.0
var _blocked_last_frame: bool = false


## Fija los datos y el punto al que se refiere la ronda. Lo llama el enemigo al
## entrar en el árbol.
func configure(archetype: EnemyArchetype, anchor: Vector2) -> void:
	_archetype = archetype
	_anchor = anchor


## Recalcula el intent de este frame. `body` es el cuerpo que se mueve y `eyes`
## lo que ve; ninguno se guarda.
func decide(body: CharacterBody2D, eyes: Perception, delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_intent.clear_edges()
	if _archetype == null:
		_intent.move = 0.0
		return

	var target := _pick_target(body, eyes)
	var goal_x := _goal_x(body, target)
	var distance := goal_x - body.global_position.x

	_intent.move = 0.0
	if absf(distance) > _arrival_margin():
		_intent.move = signf(distance)

	if target != null and absf(distance) <= _archetype.attack_range \
			and _attack_cooldown_left <= 0.0:
		_intent.attack_pressed = true
		_attack_cooldown_left = _archetype.attack_cooldown
		# Encarar a la víctima aunque ya no haga falta andar hacia ella.
		if absf(distance) > 1.0:
			_intent.move = signf(distance)

	_request_jump_if_blocked(body)


## A quién perseguir, y de paso en qué modo se está. La histéresis entre
## `detection_range` y `leash_range` es lo que evita el parpadeo
## PATROL↔CHASE de quien se queda justo en el borde del radio.
func _pick_target(body: CharacterBody2D, eyes: Perception) -> Node2D:
	var seen: Node2D = eyes.closest_to(body.global_position) if eyes != null else null
	if seen != null:
		var distance := body.global_position.distance_to(seen.global_position)
		if distance <= _archetype.leash_range:
			mode = Mode.CHASE
			return seen
	if mode == Mode.CHASE:
		mode = Mode.RETURN
	return null


func _goal_x(body: CharacterBody2D, target: Node2D) -> float:
	if target != null:
		return target.global_position.x

	if mode == Mode.RETURN:
		if absf(body.global_position.x - _anchor.x) <= _arrival_margin():
			mode = Mode.PATROL
		else:
			return _anchor.x

	# Ronda: se da la vuelta al llegar al extremo.
	var offset := body.global_position.x - _anchor.x
	if absf(offset) >= _archetype.patrol_radius:
		_patrol_direction = -signf(offset)
	return _anchor.x + _archetype.patrol_radius * _patrol_direction


## Salta cuando el cuerpo se queda pegado a una pared yendo hacia ella. No se
## sondea el terreno con raycasts propios: se mira lo que el motor ya sabe tras
## `move_and_slide` (§13).
func _request_jump_if_blocked(body: CharacterBody2D) -> void:
	var pressing := absf(_intent.move) > 0.01
	var blocked := pressing and body.is_on_wall() \
			and signf(body.get_wall_normal().x) != signf(_intent.move)
	if blocked and body.is_on_floor() and not _blocked_last_frame:
		_intent.jump_pressed = true
		_intent.jump_held = true
	else:
		_intent.jump_held = false
	_blocked_last_frame = blocked


func _arrival_margin() -> float:
	return 12.0
