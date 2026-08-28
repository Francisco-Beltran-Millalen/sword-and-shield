class_name LocalIntentSource
extends IntentSource

## Lee el teclado a través del InputMap del proyecto.
##
## Las acciones se declaran en `project.godot` (`p1_left`, `p2_jump`…), no se
## registran en runtime. Por eso funcionan `Input.get_axis()`, el remapeo por
## parte del jugador y el panel de entrada del editor — tres cosas que el
## proyecto anterior perdió al construir su InputMap por código (§13).
##
## El prefijo sale de `player_index`, así que el mismo script sirve para ambos
## jugadores en cooperativo local sin ninguna rama.

@export_range(0, 1) var player_index: int = 0

var _prefix: StringName = &"p1"


func _ready() -> void:
	_prefix = &"p1" if player_index == 0 else &"p2"
	_warn_missing_actions()


func poll() -> PlayerIntent:
	_intent.move = Input.get_axis(_action(&"left"), _action(&"right"))
	_intent.up = Input.get_action_strength(_action(&"up"))
	_intent.down = Input.get_action_strength(_action(&"down"))

	_intent.jump_pressed = Input.is_action_just_pressed(_action(&"jump"))
	_intent.jump_held = Input.is_action_pressed(_action(&"jump"))
	_intent.attack_pressed = Input.is_action_just_pressed(_action(&"attack"))
	_intent.guard_held = Input.is_action_pressed(_action(&"guard"))
	_intent.tether_pressed = Input.is_action_just_pressed(_action(&"tether"))
	_intent.interact_pressed = Input.is_action_just_pressed(_action(&"interact"))

	return _intent


func _action(suffix: StringName) -> StringName:
	return StringName("%s_%s" % [_prefix, suffix])


func _warn_missing_actions() -> void:
	for suffix: StringName in [&"left", &"right", &"up", &"down", &"jump",
			&"attack", &"guard", &"tether", &"interact"]:
		var action := _action(suffix)
		if not InputMap.has_action(action):
			push_error("InputMap no tiene la acción '%s'. Revisa project.godot." % action)
