class_name StatsComponent
extends Node

## Stats base + modificadores apilables, con caché invalidada perezosamente.
##
## Los valores base se editan en el inspector. Los modificadores llegan de los
## hijos `StatModifierNode` (equipo, habilidades desbloqueadas, buffs
## temporales, efectos de terreno) y se combinan como `(base + Σadd) * Πmult`.
##
## El componente descubre sus hijos solo — al entrar o salir un
## `StatModifierNode` del árbol, la caché se invalida. Añadir un power-up es
## instanciar un nodo bajo este componente; retirarlo es liberarlo.
##
## Portado de `PhysicsStatsComponent` del proyecto Tension. El conjunto de
## StatID se reescribió: los stats del tether (arrastre, carga de tensión,
## anclaje) desaparecieron y entraron los del metroidvania.

enum StatID {
	## Locomoción
	MAX_SPEED,
	ACCELERATION,
	FRICTION,
	AIR_CONTROL,      ## 0..1 — cuánto control horizontal se conserva en el aire
	GRAVITY_SCALE,
	JUMP_VELOCITY,    ## Negativo = hacia arriba
	AIR_JUMPS,        ## Saltos adicionales en el aire (habilidad desbloqueable)

	## Combate
	DAMAGE_POWER,     ## Multiplicador del daño infligido
	DEFENSE,          ## Multiplicador del daño recibido (menor = más resistente)
	KNOCKBACK_DEALT,
	KNOCKBACK_TAKEN,
	INVULN_SECONDS,   ## Duración de i-frames tras recibir daño

	## Cuerpo
	MASS,
	IS_IMMOVABLE,     ## Booleano: fuerzas externas no lo mueven
}

@export_group("Locomoción")
@export var base_max_speed: float = 220.0
@export var base_acceleration: float = 1800.0
@export var base_friction: float = 2200.0
@export_range(0.0, 1.0, 0.01) var base_air_control: float = 0.75
@export var base_gravity_scale: float = 1.0
@export var base_jump_velocity: float = -520.0
@export var base_air_jumps: float = 0.0

@export_group("Combate")
@export var base_damage_power: float = 1.0
@export var base_defense: float = 1.0
@export var base_knockback_dealt: float = 1.0
@export var base_knockback_taken: float = 1.0
@export var base_invuln_seconds: float = 0.6

@export_group("Cuerpo")
@export var base_mass: float = 5.0
@export var base_is_immovable: bool = false

var _is_dirty: bool = true
var _cached: Dictionary = {}


func _ready() -> void:
	child_entered_tree.connect(_on_child_hierarchy_changed)
	child_exiting_tree.connect(_on_child_hierarchy_changed)
	for child in get_children():
		_on_child_hierarchy_changed(child)


func get_stat(id: StatID) -> float:
	if _is_dirty:
		_recalculate()
	return _cached.get(id, 0.0)


func get_stat_bool(id: StatID) -> bool:
	return get_stat(id) > 0.5


func get_stat_int(id: StatID) -> int:
	return int(get_stat(id))


## Invalida la caché a mano. Solo hace falta si un modificador cambia sus
## valores sin emitir `modifier_changed`.
func mark_dirty() -> void:
	_is_dirty = true


func _base_values() -> Dictionary:
	return {
		StatID.MAX_SPEED: base_max_speed,
		StatID.ACCELERATION: base_acceleration,
		StatID.FRICTION: base_friction,
		StatID.AIR_CONTROL: base_air_control,
		StatID.GRAVITY_SCALE: base_gravity_scale,
		StatID.JUMP_VELOCITY: base_jump_velocity,
		StatID.AIR_JUMPS: base_air_jumps,
		StatID.DAMAGE_POWER: base_damage_power,
		StatID.DEFENSE: base_defense,
		StatID.KNOCKBACK_DEALT: base_knockback_dealt,
		StatID.KNOCKBACK_TAKEN: base_knockback_taken,
		StatID.INVULN_SECONDS: base_invuln_seconds,
		StatID.MASS: base_mass,
		StatID.IS_IMMOVABLE: 1.0 if base_is_immovable else 0.0,
	}


func _recalculate() -> void:
	_cached = _base_values()

	var adds: Dictionary = {}
	var mults: Dictionary = {}
	for child in get_children():
		var source := child as StatModifierNode
		if source == null:
			continue
		for mod in source.get_modifiers():
			adds[mod.stat_id] = adds.get(mod.stat_id, 0.0) + mod.add_value
			mults[mod.stat_id] = mults.get(mod.stat_id, 1.0) * mod.mult_value

	for stat_id: StatID in _cached.keys():
		var base: float = _cached[stat_id]
		_cached[stat_id] = (base + adds.get(stat_id, 0.0)) * mults.get(stat_id, 1.0)

	_is_dirty = false


func _on_child_hierarchy_changed(node: Node) -> void:
	var source := node as StatModifierNode
	if source != null and not source.modifier_changed.is_connected(mark_dirty):
		source.modifier_changed.connect(mark_dirty)
	_is_dirty = true
