class_name ShieldKit
extends PlayerKit

## Kit defensivo. La guardia es un estado sostenido, no un golpe.
##
## Mientras el botón siga pulsado la `GuardBox` está levantada; al soltarlo
## baja. La ventana de parry la mide un `Timer` dentro de la propia GuardBox
## (§13) y se abre en el instante de levantar, así que un bloqueo reactivo y
## bien medido premia con parry.
##
## Contrapartida: con la guardia alta el jugador se mueve más lento. Eso no se
## escribe sobre el Player — se expresa como un `StatModifierNode` que el
## `StatsComponent` recoge solo (§2).

## Multiplicador de velocidad mientras se guarda.
@export_range(0.05, 1.0, 0.05) var guard_speed_scale: float = 0.45
## Empuje hacia atrás al encajar un bloqueo normal.
@export var block_recoil: float = 90.0

@onready var guard_box: GuardBox = $GuardBox

var _guarding: bool = false


func _ready() -> void:
	kit_id = &"shield"
	display_name = "Escudo"
	if guard_box != null and not guard_box.blocked.is_connected(_on_blocked):
		guard_box.blocked.connect(_on_blocked)


func tick(player: Node, intent: PlayerIntent, _delta: float) -> void:
	var wants_guard: bool = intent.guard_held
	if wants_guard == _guarding:
		if _guarding:
			_refresh_facing(player, intent)
		return

	if wants_guard:
		_raise(player, intent)
	else:
		_lower()


func on_action_released(_player: Node) -> void:
	_lower()


func on_interrupted(player: Node) -> void:
	_lower()
	super.on_interrupted(player)


func animation_override() -> StringName:
	return &"guard" if _guarding else &""


## Lo consulta el Player para escalar la velocidad. Se expone como consulta en
## vez de escribirse sobre el jugador (§2).
func speed_scale() -> float:
	return guard_speed_scale if _guarding else 1.0


func _raise(player: Node, intent: PlayerIntent) -> void:
	_guarding = true
	_set_busy(true)
	var facing := _resolve_facing(player, intent)
	if guard_box != null:
		guard_box.raise(facing)


func _lower() -> void:
	if not _guarding:
		return
	_guarding = false
	_set_busy(false)
	if guard_box != null:
		guard_box.lower()


func _refresh_facing(player: Node, intent: PlayerIntent) -> void:
	var facing := _resolve_facing(player, intent)
	if guard_box == null or facing == 0:
		return
	# `set_facing` y no `raise`: girarse mientras se bloquea no debe reabrir la
	# ventana de parry.
	guard_box.set_facing(facing)
	scale.x = float(facing)


func _resolve_facing(player: Node, intent: PlayerIntent) -> int:
	var facing: int = intent.facing()
	if facing == 0 and player.has_method("get_facing"):
		facing = player.get_facing()
	return facing if facing != 0 else 1


func _on_blocked(hitbox: Node, perfect: bool) -> void:
	# Se emitía `(self, hitbox, …)`: el kit como guardia y la HITBOX como
	# atacante. Cualquier consumidor habría recibido un volumen creyendo tener
	# la entidad. Ahora van la guardia y el atacante de verdad.
	var attacker: Node = hitbox.attacker() if hitbox.has_method("attacker") else null
	GameEvents.hit_guarded.emit(guard_box, attacker, perfect)
	if perfect:
		return   ## El parry no empuja: esa es su recompensa.
	if block_recoil > 0.0:
		var away := Vector2(-scale.x, 0.0).normalized()
		impulse_requested.emit(away * block_recoil)
