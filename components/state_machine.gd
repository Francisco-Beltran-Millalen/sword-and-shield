class_name StateMachine
extends Node

## Centralizes state transitions and notifications for a host node.
##
## Attach it as a child of any entity with an enum-based state set (Player,
## Enemy, NPC, etc.). Each call to `transition_to(new_state)` runs the
## previous state's `on_exit` hook, the new state's `on_enter` hook, and
## emits `state_changed`. It is idempotent: if `new_state == current_state`,
## it does nothing.
##
## Designed to work with int enums (no per-state classes required).
## For networking support, replicate `StateMachine:replicated_state`
## from the host's `MultiplayerSynchronizer`.

signal state_changed(from_state: int, to_state: int)
signal state_entered(state: int)
signal state_exited(state: int)

const STATE_UNDEFINED := -1

var _current_state: int = STATE_UNDEFINED
var _previous_state: int = STATE_UNDEFINED

var _on_enter: Dictionary = {}
var _on_exit: Dictionary = {}
var _state_names: Dictionary = {}

var current_state: int:
	get:
		return _current_state

## Replication-facing property. Use this instead of `current_state` in
## `MultiplayerSynchronizer` so remote peers replay enter/exit callbacks and
## transition signals.
var replicated_state: int:
	get:
		return _current_state
	set(value):
		_transition_to_internal(value, is_node_ready())

var previous_state: int:
	get:
		return _previous_state


## Sets the initial state without firing callbacks or signals.
## Use in `_ready` before the first real transition.
func init_state(state: int) -> void:
	_current_state = state
	_previous_state = STATE_UNDEFINED


## Transitions to `new_state`. Returns `true` if the transition happened,
## `false` if we were already in that state.
##
## Execution order:
##   1. old state's on_exit (receives `to_state`)
##   2. signal state_exited(old)
##   3. new state's on_enter (receives `from_state`)
##   4. signal state_entered(new)
##   5. signal state_changed(old, new)
func transition_to(new_state: int) -> bool:
	return _transition_to_internal(new_state, true)


## Re-emits the current state as if it had just been entered.
## Useful after connecting listeners in `_ready`.
func emit_current() -> void:
	if _current_state == STATE_UNDEFINED:
		return
	state_entered.emit(_current_state)
	state_changed.emit(STATE_UNDEFINED, _current_state)


## Registers a callable that runs when ENTERING `state`.
## The callable receives `from_state: int` (the state we came from).
func set_on_enter(state: int, callback: Callable) -> void:
	_on_enter[state] = callback


## Registers a callable that runs when EXITING `state`.
## The callable receives `to_state: int` (the state we are moving to).
## Useful when cleanup depends on the destination, e.g. not canceling wall
## interaction when moving from WALL_HOLDING to WALL_SLIDING.
func set_on_exit(state: int, callback: Callable) -> void:
	_on_exit[state] = callback


## Associates a readable name with the state (debug/HUD). Optional.
func set_state_name(state: int, state_name: String) -> void:
	_state_names[state] = state_name


func get_state_name(state: int = current_state) -> String:
	return _state_names.get(state, str(state))


func is_in(state: int) -> bool:
	return _current_state == state


func is_in_any(states: Array) -> bool:
	return _current_state in states


func is_not_in(state: int) -> bool:
	return _current_state != state


func _transition_to_internal(new_state: int, emit_side_effects: bool) -> bool:
	if new_state == _current_state:
		return false

	var old_state := _current_state
	_previous_state = old_state
	_current_state = new_state

	if not emit_side_effects:
		return true

	if old_state != STATE_UNDEFINED:
		var exit_cb: Callable = _on_exit.get(old_state, Callable())
		if exit_cb.is_valid():
			exit_cb.call(new_state)
		state_exited.emit(old_state)

	var enter_cb: Callable = _on_enter.get(new_state, Callable())
	if enter_cb.is_valid():
		enter_cb.call(old_state)
	state_entered.emit(new_state)
	state_changed.emit(old_state, new_state)
	return true
