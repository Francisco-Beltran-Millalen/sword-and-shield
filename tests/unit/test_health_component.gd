# Run with GUT addon: godot --headless -s addons/gut/gut_cmdln.gd
extends "res://addons/gut/test.gd"

var _health: HealthComponent


func _make_component(max_hp: int = 5, starting: int = -1, invuln: float = 0.0) -> HealthComponent:
	var component := HealthComponent.new()
	component.max_health = max_hp
	component.starting_health = starting
	component.invulnerability_seconds = invuln
	add_child(component)
	return component


func before_each() -> void:
	_health = null


func after_each() -> void:
	if _health != null:
		_health.free()
		_health = null


func test_initial_health_equals_max_when_starting_unset() -> void:
	_health = _make_component(8)
	assert_eq(_health.current_health, 8, "Initial HP should match max_health")
	assert_false(_health.is_dead, "Should not start dead with positive HP")


func test_starting_health_overrides_max() -> void:
	_health = _make_component(10, 3)
	assert_eq(_health.current_health, 3, "starting_health should override max_health")
	assert_false(_health.is_dead)


func test_starting_health_zero_marks_dead() -> void:
	_health = _make_component(10, 0)
	assert_eq(_health.current_health, 0)
	assert_true(_health.is_dead, "Starting at 0 HP should mark the entity as dead")


func test_take_damage_reduces_current_health() -> void:
	_health = _make_component(5)
	var applied := _health.take_damage(2)
	assert_eq(applied, 2, "Should report applied damage")
	assert_eq(_health.current_health, 3)


func test_take_damage_clamps_to_zero() -> void:
	_health = _make_component(5)
	var applied := _health.take_damage(99)
	assert_eq(applied, 5, "Damage in excess of HP should clamp to remaining HP")
	assert_eq(_health.current_health, 0)
	assert_true(_health.is_dead)


func test_take_damage_emits_signals() -> void:
	_health = _make_component(5)
	watch_signals(_health)
	_health.take_damage(2)
	assert_signal_emitted(_health, "damaged")
	assert_signal_emitted(_health, "health_changed")
	assert_signal_emit_count(_health, "depleted", 0)


func test_depleted_fires_once_when_health_hits_zero() -> void:
	_health = _make_component(3)
	watch_signals(_health)
	_health.take_damage(3)
	assert_signal_emit_count(_health, "depleted", 1)
	# Further damage on a dead unit should not re-fire depleted.
	_health.take_damage(1)
	assert_signal_emit_count(_health, "depleted", 1)


func test_take_damage_ignored_when_dead() -> void:
	_health = _make_component(2)
	_health.take_damage(2)
	var applied := _health.take_damage(1)
	assert_eq(applied, 0, "Dead entities should not take more damage")


func test_heal_increases_health() -> void:
	_health = _make_component(10)
	_health.take_damage(6)
	assert_eq(_health.current_health, 4)
	var applied := _health.heal(3)
	assert_eq(applied, 3)
	assert_eq(_health.current_health, 7)


func test_heal_caps_at_max() -> void:
	_health = _make_component(5)
	_health.take_damage(2)
	var applied := _health.heal(99)
	assert_eq(applied, 2, "Heal should report only the amount that fit under max")
	assert_eq(_health.current_health, 5)


func test_heal_does_nothing_when_dead() -> void:
	_health = _make_component(5)
	_health.take_damage(5)
	var applied := _health.heal(3)
	assert_eq(applied, 0)
	assert_eq(_health.current_health, 0)
	assert_true(_health.is_dead, "Heal should not bring a dead entity back; use revive()")


func test_heal_full_restores_to_max() -> void:
	_health = _make_component(7)
	_health.take_damage(4)
	_health.heal_full()
	assert_eq(_health.current_health, 7)


func test_kill_sets_zero_and_emits_depleted() -> void:
	_health = _make_component(5)
	watch_signals(_health)
	_health.kill()
	assert_eq(_health.current_health, 0)
	assert_true(_health.is_dead)
	assert_signal_emit_count(_health, "depleted", 1)


func test_revive_restores_max_by_default() -> void:
	_health = _make_component(8)
	_health.kill()
	assert_true(_health.is_dead)
	watch_signals(_health)
	_health.revive()
	assert_false(_health.is_dead)
	assert_eq(_health.current_health, 8)
	assert_signal_emit_count(_health, "revived", 1)


func test_revive_with_custom_health() -> void:
	_health = _make_component(10)
	_health.kill()
	_health.revive(3)
	assert_eq(_health.current_health, 3)
	assert_false(_health.is_dead)


func test_revive_clamps_above_max() -> void:
	_health = _make_component(5)
	_health.kill()
	_health.revive(99)
	assert_eq(_health.current_health, 5, "Revive should clamp HP to max")


func test_revive_on_living_entity_acts_as_heal() -> void:
	_health = _make_component(10)
	_health.take_damage(7)
	_health.revive()
	assert_eq(_health.current_health, 10)


func test_invulnerability_blocks_damage() -> void:
	_health = _make_component(10, -1, 0.5)
	_health.take_damage(2)
	assert_eq(_health.current_health, 8)
	var applied := _health.take_damage(2)
	assert_eq(applied, 0, "Damage during i-frames should be ignored")
	assert_eq(_health.current_health, 8)
	assert_true(_health.is_invulnerable())


func test_accepts_damage_false_blocks_take_damage() -> void:
	_health = _make_component(5)
	_health.accepts_damage = false
	var applied := _health.take_damage(2)
	assert_eq(applied, 0)
	assert_eq(_health.current_health, 5)


func test_replicated_health_updates_dead_state_and_emits_depleted() -> void:
	_health = _make_component(5)
	watch_signals(_health)
	_health.replicated_health = 0
	assert_eq(_health.current_health, 0)
	assert_true(_health.is_dead)
	assert_signal_emit_count(_health, "damaged", 1)
	assert_signal_emit_count(_health, "health_changed", 1)
	assert_signal_emit_count(_health, "depleted", 1)


func test_replicated_health_revives_and_emits_revived() -> void:
	_health = _make_component(5)
	_health.kill()
	watch_signals(_health)
	_health.replicated_health = 3
	assert_eq(_health.current_health, 3)
	assert_false(_health.is_dead)
	assert_signal_emit_count(_health, "revived", 1)
	assert_signal_emit_count(_health, "health_changed", 1)
	assert_signal_emit_count(_health, "healed", 0)


func test_set_max_health_clamps_current_when_smaller() -> void:
	_health = _make_component(10)
	_health.set_max_health(4)
	assert_eq(_health.max_health, 4)
	assert_eq(_health.current_health, 4, "Current HP should clamp to new max")


func test_set_max_health_with_refill() -> void:
	_health = _make_component(5)
	_health.take_damage(3)
	_health.set_max_health(10, true)
	assert_eq(_health.max_health, 10)
	assert_eq(_health.current_health, 10)


func test_get_health_ratio() -> void:
	_health = _make_component(10)
	_health.take_damage(7)
	assert_almost_eq(_health.get_health_ratio(), 0.3, 0.0001)


func test_is_full_returns_true_only_at_max() -> void:
	_health = _make_component(5)
	assert_true(_health.is_full())
	_health.take_damage(1)
	assert_false(_health.is_full())
	_health.heal_full()
	assert_true(_health.is_full())
