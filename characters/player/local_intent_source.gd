class_name LocalIntentSource
extends IntentSource

## Lee el teclado a través del InputMap del proyecto.
##
## Las acciones se declaran en `project.godot`, no se registran en runtime. Por
## eso funcionan `Input.get_axis()`, el remapeo por parte del jugador y el panel
## de entrada del editor — tres cosas que el proyecto anterior perdió al
## construir su InputMap por código (§13).
##
## Un solo juego de acciones, sin prefijo por jugador: el juego es en red y cada
## cliente controla un personaje. Esta fuente solo se consulta en el peer que
## tiene autoridad sobre su `Player`; los personajes remotos no simulan.

const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"attack", &"guard", &"tether", &"interact",
]


func _ready() -> void:
	_warn_missing_actions()


func poll() -> PlayerIntent:
	_intent.move = Input.get_axis(&"move_left", &"move_right")
	_intent.up = Input.get_action_strength(&"move_up")
	_intent.down = Input.get_action_strength(&"move_down")

	_intent.jump_pressed = Input.is_action_just_pressed(&"jump")
	_intent.jump_held = Input.is_action_pressed(&"jump")
	_intent.attack_pressed = Input.is_action_just_pressed(&"attack")
	_intent.guard_held = Input.is_action_pressed(&"guard")
	_intent.tether_pressed = Input.is_action_just_pressed(&"tether")
	_intent.interact_pressed = Input.is_action_just_pressed(&"interact")

	return _intent


func _warn_missing_actions() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			push_error("InputMap no tiene la acción '%s'. Revisa project.godot." % action)
