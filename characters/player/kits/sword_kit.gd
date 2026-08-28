class_name SwordKit
extends PlayerKit

## Kit ofensivo. Traduce la intención del jugador a peticiones al `Attacker`.
##
## El combo, las ventanas de daño y las animaciones **no viven aquí**: son del
## `Attacker`, que es un componente que también usarán enemigos y trampas. Este
## script solo hace de puente entre el intent del jugador y ese componente, y
## reenvía hacia arriba lo que ocurra.
##
## Que quede tan corto es la señal de que la abstracción está en su sitio: si
## mañana un enemigo necesita el mismo combo de tres golpes, reutiliza el
## `Attacker` y sus `AttackData`, no este archivo.

@onready var attacker: Attacker = $Attacker


func _ready() -> void:
	kit_id = &"sword"
	display_name = "Espada"
	if attacker == null:
		push_error("SwordKit necesita un nodo Attacker.")
		return
	attacker.attack_started.connect(_on_attack_started)
	attacker.chain_ended.connect(_on_chain_ended)
	attacker.lunge_requested.connect(_on_lunge_requested)
	attacker.hit_landed.connect(_on_hit_landed)


func on_action_pressed(player: Node, intent: PlayerIntent) -> void:
	if attacker == null:
		return
	attacker.attack(_resolve_facing(player, intent))


func on_interrupted(player: Node) -> void:
	if attacker != null:
		attacker.interrupt()
	super.on_interrupted(player)


func animation_override() -> StringName:
	if attacker == null or not attacker.is_attacking():
		return &""
	var data := attacker.current_attack()
	return data.animation if data != null else &""


func _resolve_facing(player: Node, intent: PlayerIntent) -> int:
	var facing: int = intent.facing()
	if facing == 0 and player.has_method("get_facing"):
		facing = player.get_facing()
	return facing if facing != 0 else 1


func _on_attack_started(_data: AttackData, _index: int) -> void:
	_set_busy(true)


func _on_chain_ended() -> void:
	_set_busy(false)


func _on_lunge_requested(impulse: Vector2) -> void:
	# El kit no mueve al jugador: reenvía la petición hacia arriba (§2).
	impulse_requested.emit(Vector2(impulse.x * signf(scale.x if scale.x != 0.0 else 1.0), impulse.y))


func _on_hit_landed(hurtbox: Hurtbox, _position: Vector2, data: AttackData) -> void:
	var target := hurtbox.get_parent()
	GameEvents.hit_landed.emit(get_parent(), target, data.damage if data != null else 0)
