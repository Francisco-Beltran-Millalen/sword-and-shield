class_name HealthComponent
extends Node

## Reusable health / damage / death component.
##
## Attach it as a child of any damageable node (Player, Enemy, destructible
## prop, etc.). The component only tracks HP and emits signals; the host
## decides the consequence (enter KO, hide the sprite, queue_free, etc.)
## by connecting to `depleted`.
##
## For networking support, have the host node's `MultiplayerSynchronizer`
## replicate the `HealthComponent:replicated_health` property (on_change mode).

signal health_changed(new_health: int, max_health: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal depleted(source: Node)
signal revived(new_health: int)

@export var max_health: int = 5
## Initial HP when entering the tree. -1 means "use `max_health`".
@export var starting_health: int = -1
## Seconds of invulnerability after taking damage. 0 disables it.
@export var invulnerability_seconds: float = 0.0
## If false, `take_damage` is ignored (cinematic / god mode).
@export var accepts_damage: bool = true

var _current_health: int = 0
var _received_replication_before_ready: bool = false
var is_dead: bool = false

var _invuln_timer: float = 0.0

var current_health: int:
	get:
		return _current_health

## Replication-facing property. Use this instead of `current_health` in
## `MultiplayerSynchronizer` so remote peers replay the component's derived
## state updates and outward-facing signals.
var replicated_health: int:
	get:
		return _current_health
	set(value):
		if not is_node_ready():
			_received_replication_before_ready = true
		_apply_replicated_health(value)


func _ready() -> void:
	set_process(false)
	if _received_replication_before_ready:
		_current_health = clampi(_current_health, 0, max_health)
	else:
		_current_health = max_health if starting_health < 0 else clampi(starting_health, 0, max_health)
	is_dead = _current_health <= 0
	health_changed.emit(_current_health, max_health)


func _process(delta: float) -> void:
	if _invuln_timer <= 0.0:
		set_process(false)
		return
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)
	if _invuln_timer <= 0.0:
		set_process(false)


## Applies damage. Returns the amount actually applied.
## Returns 0 if dead, invulnerable, or not accepting damage.
func take_damage(amount: int = 1, source: Node = null) -> int:
	if amount <= 0 or is_dead or not accepts_damage or is_invulnerable():
		return 0

	var applied := mini(amount, _current_health)
	_current_health -= applied

	if invulnerability_seconds > 0.0:
		_invuln_timer = invulnerability_seconds
		set_process(true)

	damaged.emit(applied, source)
	health_changed.emit(_current_health, max_health)

	if _current_health <= 0:
		is_dead = true
		depleted.emit(source)

	return applied


## Heals. Returns the amount actually restored (0 if dead or already full).
func heal(amount: int) -> int:
	if amount <= 0 or is_dead:
		return 0

	var applied := mini(amount, max_health - _current_health)
	if applied <= 0:
		return 0

	_current_health += applied
	healed.emit(applied)
	health_changed.emit(_current_health, max_health)
	return applied


## Fully heals. Does not revive if already dead (use `revive` for that).
func heal_full() -> void:
	if is_dead:
		return
	var applied := max_health - _current_health
	if applied <= 0:
		return
	_current_health = max_health
	healed.emit(applied)
	health_changed.emit(_current_health, max_health)


## Brings HP to 0 instantly (scripted kill, cinematic defeat).
func kill(source: Node = null) -> void:
	if is_dead:
		return
	var applied := _current_health
	_current_health = 0
	is_dead = true
	if applied > 0:
		damaged.emit(applied, source)
	health_changed.emit(_current_health, max_health)
	depleted.emit(source)


## Revives from death (respawn / second chance).
## `with_health = -1` restores to full. If the entity was not dead,
## this behaves like heal up to the requested value.
func revive(with_health: int = -1) -> void:
	var target := max_health if with_health < 0 else clampi(with_health, 1, max_health)

	if not is_dead:
		if target > _current_health:
			heal(target - _current_health)
		return

	_current_health = target
	is_dead = false
	_invuln_timer = 0.0
	set_process(false)
	revived.emit(_current_health)
	health_changed.emit(_current_health, max_health)


## Changes the HP cap. `refill = true` also restores current HP to the new max.
func set_max_health(new_max: int, refill: bool = false) -> void:
	new_max = maxi(new_max, 1)
	max_health = new_max
	if refill:
		_current_health = new_max
		is_dead = false
	else:
		_current_health = mini(_current_health, max_health)
		is_dead = _current_health <= 0
	health_changed.emit(_current_health, max_health)


func is_full() -> bool:
	return _current_health >= max_health


func is_invulnerable() -> bool:
	return _invuln_timer > 0.0


func get_health_ratio() -> float:
	if max_health <= 0:
		return 0.0
	return float(_current_health) / float(max_health)


func _apply_replicated_health(value: int) -> void:
	var clamped_value := clampi(value, 0, max_health)
	if clamped_value == _current_health:
		return

	var old_health := _current_health
	var was_dead := is_dead
	_current_health = clamped_value
	is_dead = _current_health <= 0

	if not is_node_ready():
		return

	if was_dead and not is_dead:
		revived.emit(_current_health)
		health_changed.emit(_current_health, max_health)
		return

	var delta := _current_health - old_health
	if delta < 0:
		damaged.emit(-delta, null)
	elif delta > 0:
		healed.emit(delta)
	health_changed.emit(_current_health, max_health)

	if not was_dead and is_dead:
		depleted.emit(null)
