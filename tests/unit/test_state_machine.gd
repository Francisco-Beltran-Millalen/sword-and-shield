# Run with GUT addon: godot --headless -s addons/gut/gut_cmdln.gd
extends "res://addons/gut/test.gd"

# Test states (we do not depend on the Player enum so the test validates
# the component in isolation).
const STATE_IDLE := 0
const STATE_RUN := 1
const STATE_JUMP := 2
const STATE_DEAD := 3

var _sm: StateMachine

# Callback trackers
var _enter_calls: Array = []
var _exit_calls: Array = []


func before_each() -> void:
	_sm = StateMachine.new()
	add_child(_sm)
	_enter_calls.clear()
	_exit_calls.clear()


func after_each() -> void:
	_sm.free()
	_sm = null


func _track_enter(state_label: String) -> Callable:
	return func(from_state: int) -> void:
		_enter_calls.append([state_label, from_state])


func _track_exit(state_label: String) -> Callable:
	return func(to_state: int) -> void:
		_exit_calls.append([state_label, to_state])


func test_initial_state_is_undefined() -> void:
	assert_eq(_sm.current_state, StateMachine.STATE_UNDEFINED)
	assert_eq(_sm.previous_state, StateMachine.STATE_UNDEFINED)


func test_init_state_does_not_emit_signals() -> void:
	watch_signals(_sm)
	_sm.init_state(STATE_IDLE)
	assert_eq(_sm.current_state, STATE_IDLE)
	assert_signal_emit_count(_sm, "state_changed", 0)
	assert_signal_emit_count(_sm, "state_entered", 0)
	assert_signal_emit_count(_sm, "state_exited", 0)


func test_transition_to_changes_state_and_emits_signals() -> void:
	_sm.init_state(STATE_IDLE)
	watch_signals(_sm)
	var ok := _sm.transition_to(STATE_RUN)
	assert_true(ok, "Transition to a different state should return true")
	assert_eq(_sm.current_state, STATE_RUN)
	assert_eq(_sm.previous_state, STATE_IDLE)
	assert_signal_emit_count(_sm, "state_changed", 1)
	assert_signal_emit_count(_sm, "state_entered", 1)
	assert_signal_emit_count(_sm, "state_exited", 1)


func test_transition_to_same_state_is_no_op() -> void:
	_sm.init_state(STATE_RUN)
	watch_signals(_sm)
	var ok := _sm.transition_to(STATE_RUN)
	assert_false(ok, "Re-transitioning to same state should return false")
	assert_signal_emit_count(_sm, "state_changed", 0)


func test_signal_state_changed_carries_from_and_to() -> void:
	_sm.init_state(STATE_IDLE)
	watch_signals(_sm)
	_sm.transition_to(STATE_RUN)
	var params: Array = get_signal_parameters(_sm, "state_changed", 0)
	assert_eq(params[0], STATE_IDLE, "from_state should be the previous state")
	assert_eq(params[1], STATE_RUN, "to_state should be the new state")


func test_on_enter_callback_fires_with_from_state() -> void:
	_sm.set_on_enter(STATE_RUN, _track_enter("RUN"))
	_sm.init_state(STATE_IDLE)
	_sm.transition_to(STATE_RUN)
	assert_eq(_enter_calls.size(), 1)
	assert_eq(_enter_calls[0][0], "RUN")
	assert_eq(_enter_calls[0][1], STATE_IDLE,
		"on_enter should receive the state we came from")


func test_on_exit_callback_fires_with_to_state() -> void:
	_sm.set_on_exit(STATE_IDLE, _track_exit("IDLE"))
	_sm.init_state(STATE_IDLE)
	_sm.transition_to(STATE_RUN)
	assert_eq(_exit_calls.size(), 1)
	assert_eq(_exit_calls[0][0], "IDLE")
	assert_eq(_exit_calls[0][1], STATE_RUN,
		"on_exit should receive the state we are heading to")


func test_on_enter_does_not_fire_for_undefined_initial() -> void:
	# init_state should not trigger on_enter, even if a callback is registered.
	_sm.set_on_enter(STATE_IDLE, _track_enter("IDLE"))
	_sm.init_state(STATE_IDLE)
	assert_eq(_enter_calls.size(), 0,
		"init_state should not invoke on_enter callbacks")


func test_on_exit_does_not_fire_when_previous_state_undefined() -> void:
	# First real transition starts from STATE_UNDEFINED — no exit callback fires.
	_sm.set_on_exit(STATE_IDLE, _track_exit("IDLE"))
	_sm.transition_to(STATE_IDLE)
	assert_eq(_exit_calls.size(), 0,
		"No on_exit should fire when transitioning from UNDEFINED")


func test_callback_can_distinguish_destination() -> void:
	# Common pattern: callback returns early for some destinations.
	var skipped_destinations: Array = []
	var triggered_destinations: Array = []
	var cb := func(to_state: int) -> void:
		if to_state == STATE_JUMP:
			skipped_destinations.append(to_state)
			return
		triggered_destinations.append(to_state)
	_sm.set_on_exit(STATE_RUN, cb)
	_sm.init_state(STATE_RUN)
	_sm.transition_to(STATE_JUMP)
	_sm.transition_to(STATE_RUN)
	_sm.transition_to(STATE_IDLE)
	assert_eq(skipped_destinations, [STATE_JUMP])
	assert_eq(triggered_destinations, [STATE_IDLE])


func test_is_in_returns_correct_value() -> void:
	_sm.init_state(STATE_IDLE)
	assert_true(_sm.is_in(STATE_IDLE))
	assert_false(_sm.is_in(STATE_RUN))


func test_is_in_any_matches_first_present() -> void:
	_sm.init_state(STATE_RUN)
	assert_true(_sm.is_in_any([STATE_IDLE, STATE_RUN, STATE_JUMP]))
	assert_false(_sm.is_in_any([STATE_IDLE, STATE_DEAD]))


func test_is_not_in_returns_correct_value() -> void:
	_sm.init_state(STATE_IDLE)
	assert_true(_sm.is_not_in(STATE_RUN))
	assert_false(_sm.is_not_in(STATE_IDLE))


func test_state_names_default_to_string_id() -> void:
	assert_eq(_sm.get_state_name(STATE_IDLE), "0")


func test_state_names_use_registered_label() -> void:
	_sm.set_state_name(STATE_IDLE, "IDLE")
	_sm.set_state_name(STATE_RUN, "RUN")
	_sm.init_state(STATE_RUN)
	assert_eq(_sm.get_state_name(STATE_IDLE), "IDLE")
	assert_eq(_sm.get_state_name(), "RUN", "Default arg should return current state's name")


func test_emit_current_re_emits_state_entered_and_changed() -> void:
	_sm.init_state(STATE_IDLE)
	watch_signals(_sm)
	_sm.emit_current()
	assert_signal_emit_count(_sm, "state_entered", 1)
	assert_signal_emit_count(_sm, "state_changed", 1)
	var params: Array = get_signal_parameters(_sm, "state_changed", 0)
	assert_eq(params[0], StateMachine.STATE_UNDEFINED)
	assert_eq(params[1], STATE_IDLE)


func test_emit_current_no_op_when_undefined() -> void:
	watch_signals(_sm)
	_sm.emit_current()
	assert_signal_emit_count(_sm, "state_entered", 0)
	assert_signal_emit_count(_sm, "state_changed", 0)


func test_replicated_state_updates_previous_and_emits_transition_signals() -> void:
	_sm.init_state(STATE_IDLE)
	watch_signals(_sm)
	_sm.replicated_state = STATE_RUN
	assert_eq(_sm.current_state, STATE_RUN)
	assert_eq(_sm.previous_state, STATE_IDLE)
	assert_signal_emit_count(_sm, "state_exited", 1)
	assert_signal_emit_count(_sm, "state_entered", 1)
	assert_signal_emit_count(_sm, "state_changed", 1)


func test_replicated_state_runs_registered_callbacks() -> void:
	var trace: Array = []
	_sm.set_on_exit(STATE_IDLE, func(to_state: int) -> void: trace.append("exit:%d" % to_state))
	_sm.set_on_enter(STATE_RUN, func(from_state: int) -> void: trace.append("enter:%d" % from_state))
	_sm.init_state(STATE_IDLE)
	_sm.replicated_state = STATE_RUN
	assert_eq(trace, ["exit:%d" % STATE_RUN, "enter:%d" % STATE_IDLE])


func test_chain_of_transitions_tracks_previous_correctly() -> void:
	_sm.init_state(STATE_IDLE)
	_sm.transition_to(STATE_RUN)
	assert_eq(_sm.previous_state, STATE_IDLE)
	_sm.transition_to(STATE_JUMP)
	assert_eq(_sm.previous_state, STATE_RUN)
	_sm.transition_to(STATE_IDLE)
	assert_eq(_sm.previous_state, STATE_JUMP)


func test_callback_order_exit_before_enter() -> void:
	var trace: Array = []
	_sm.set_on_exit(STATE_IDLE, func(_to: int) -> void: trace.append("exit_idle"))
	_sm.set_on_enter(STATE_RUN, func(_from: int) -> void: trace.append("enter_run"))
	_sm.init_state(STATE_IDLE)
	_sm.transition_to(STATE_RUN)
	assert_eq(trace, ["exit_idle", "enter_run"],
		"on_exit must run before on_enter")
