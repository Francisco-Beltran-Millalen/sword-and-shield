class_name Enemy
extends CharacterBody2D

## Un enemigo: el mismo montaje que el jugador con otra fuente de intenciones.
##
## No estrena ningún sistema. `Locomotion`, `StatsComponent`, `HealthComponent`,
## `StateMachine`, `Hurtbox`, `DamageReceiver`, `Attacker`, `AttackData` y
## `Hitbox` son los que ya usaba el jugador, sin una línea añadida para él. Lo
## único propio es `AIIntentSource`, que rellena el mismo `PlayerIntent` que
## rellena el teclado (§10).
##
## Si para meter un enemigo hubiera hecho falta escribir un motor de movimiento
## o un sistema de combate nuevos, la conclusión no sería que el enemigo es
## raro: sería que los que había estaban acoplados al jugador.
##
## Los números salen del `EnemyArchetype`, y este nodo los reparte entre sus
## hijos al arrancar — escribir en lo que a uno le cuelga es lo que la excepción
## de orquestación de §2 permite. Un enemigo nuevo es un `.tres`, no un script.
##
## **Autoridad del host.** A diferencia del jugador, un enemigo lo simula
## siempre quien hospeda, y los clientes lo ven replicado. Por eso vive dentro
## de la escena de su zona: existe en los dos peers desde que la zona entra en
## el árbol, con la autoridad por defecto (el host), sin spawner ni RPC.

signal state_changed(new_state: State)
signal health_changed(current: int, maximum: int)

enum State {
	IDLE,
	WALK,
	ATTACK,
	HURT,
	DOWNED,
}

@export var archetype: EnemyArchetype

var _facing: int = 1
## Intent vacío para cuando el enemigo no manda (derrotado). Se reutiliza la
## instancia, como en `Player`: construir uno por frame es basura por cadáver.
var _idle_intent := PlayerIntent.new()

## Estado replicado, igual que en el jugador: un entero, no catorce campos.
var replicated_state: int:
	get: return state_machine.current_state if state_machine != null else State.IDLE
	set(value):
		if state_machine != null:
			state_machine.replicated_state = value

var replicated_facing: int:
	get: return _facing
	set(value):
		if value == 0 or value == _facing:
			return
		_facing = value
		_apply_facing_visuals()

@onready var stats: StatsComponent = $StatsComponent
@onready var health: HealthComponent = $HealthComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var locomotion: Locomotion = $Locomotion
@onready var intent_source: IntentSource = $IntentSource
@onready var damage_receiver: DamageReceiver = $DamageReceiver
@onready var perception: Perception = $Perception
@onready var attacker: Attacker = $Attacker
@onready var visuals: Node2D = $Visuals
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	# Quien golpea es el enemigo, no su hitbox ni el nodo que la sostiene.
	add_to_group(&"combat_source")
	add_to_group(&"enemies")
	_setup_states()
	_apply_archetype()
	health.health_changed.connect(_on_health_changed)
	health.depleted.connect(_on_depleted)
	health.revived.connect(_on_revived)
	damage_receiver.damage_taken.connect(_on_damage_taken)
	damage_receiver.knockback_requested.connect(apply_impulse)


func _physics_process(delta: float) -> void:
	# Al contrario que el jugador, al enemigo lo simula el host y punto: su
	# estado no puede ser autoritativo por cliente o cada extremo vería una
	# persecución distinta. Sin sesión de red (tests, escena suelta) simula: su
	# autoridad es la 1 por defecto y el peer offline también es el 1.
	if not is_multiplayer_authority():
		return

	if state_machine.is_in(State.DOWNED):
		locomotion.tick(self, stats, _idle_intent, delta)
		return

	var ai := intent_source as AIIntentSource
	if ai != null:
		ai.decide(self, perception, delta)
	var intent := intent_source.poll()

	_update_facing(intent)

	# Se reacciona al intent, igual que el jugador (`Player._physics_process`).
	# Así un `ScriptedIntentSource` puede conducir un enemigo en los tests sin
	# tocar la IA.
	if intent.attack_pressed:
		attacker.attack(_facing)

	locomotion.tick(self, stats, intent, delta)
	_settle_state()


func get_facing() -> int:
	return _facing


## Única vía para que algo externo lo mueva (§2), igual que en el jugador.
func apply_impulse(impulse: Vector2) -> void:
	if stats.get_stat_bool(StatsComponent.StatID.IS_IMMOVABLE):
		return
	velocity += impulse


func place_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	locomotion.reset()


func revive_full() -> void:
	health.revive()
	locomotion.reset()
	hurtbox.active = true


## Reparte los números del arquetipo entre los componentes. Es la traducción de
## un recurso de diseño a la configuración de los hijos; ninguno de ellos
## conoce `EnemyArchetype`.
func _apply_archetype() -> void:
	if archetype == null:
		return
	# `set_max_health(_, true)` y no escribir `max_health` a pelo: es la API
	# pública del componente y deja la salud actual coherente con el tope nuevo.
	health.invulnerability_seconds = archetype.invulnerability_seconds
	health.set_max_health(archetype.max_health, true)

	stats.base_max_speed = archetype.move_speed
	stats.base_acceleration = archetype.acceleration
	stats.base_friction = archetype.friction
	stats.base_jump_velocity = archetype.jump_velocity
	stats.base_defense = archetype.defense
	stats.mark_dirty()

	attacker.attacks = archetype.attacks
	perception.radius = archetype.detection_range

	var ai := intent_source as AIIntentSource
	if ai != null:
		ai.configure(archetype, global_position)

	_apply_body_size(archetype.body_size)


## El cuerpo: forma de colisión y hurtbox salen de la misma medida que el
## arquetipo. El dibujo es el rig compartido con el jugador (`body_rig.tscn`),
## dibujado a 44 px de alto: se escala con la medida del arquetipo y el color de
## rol sale por `modulate`, no duplicando polígonos.
func _apply_body_size(size: Vector2) -> void:
	var half := size * 0.5
	var centre := Vector2(0.0, -half.y)

	var rect := body_shape.shape as RectangleShape2D
	if rect != null:
		rect.size = size
	body_shape.position = centre

	var hurt_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hurt_shape != null:
		var hurt_rect := hurt_shape.shape as RectangleShape2D
		if hurt_rect != null:
			hurt_rect.size = size
		hurt_shape.position = centre

	var rig := visuals.get_node_or_null("Skeleton") as Node2D
	if rig != null:
		rig.scale = Vector2.ONE * (size.y / 44.0)
		rig.modulate = archetype.body_color


func _setup_states() -> void:
	if state_machine.current_state == StateMachine.STATE_UNDEFINED:
		state_machine.init_state(State.IDLE)
	state_machine.set_state_name(State.IDLE, "IDLE")
	state_machine.set_state_name(State.WALK, "WALK")
	state_machine.set_state_name(State.ATTACK, "ATTACK")
	state_machine.set_state_name(State.HURT, "HURT")
	state_machine.set_state_name(State.DOWNED, "DOWNED")
	state_machine.state_changed.connect(
		func(_from: int, to: int) -> void: state_changed.emit(to))


func _update_facing(intent: PlayerIntent) -> void:
	var wanted: int = intent.facing()
	if wanted == 0 or wanted == _facing:
		return
	_facing = wanted
	_apply_facing_visuals()


func _apply_facing_visuals() -> void:
	if visuals != null:
		visuals.scale.x = float(_facing)


func _settle_state() -> void:
	if state_machine.is_in(State.DOWNED):
		return
	if state_machine.is_in(State.HURT):
		if health.is_invulnerable():
			return
		state_machine.transition_to(State.IDLE)
	if attacker.is_attacking():
		state_machine.transition_to(State.ATTACK)
		return
	state_machine.transition_to(State.IDLE if absf(velocity.x) < 8.0 else State.WALK)


func _on_damage_taken(_amount: int, _from: Node, _hit_position: Vector2) -> void:
	if health.is_dead:
		return
	attacker.interrupt()
	state_machine.transition_to(State.HURT)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


## Al morir NO se libera el nodo: `queue_free()` en el host no se propaga a los
## clientes, y el enemigo vive dentro de la escena de la zona, no lo creó un
## spawner. Se queda derrotado y con la hurtbox apagada, y ese estado sí viaja
## por `replicated_state`.
func _on_depleted(_source: Node) -> void:
	attacker.interrupt()
	locomotion.reset()
	hurtbox.active = false
	state_machine.transition_to(State.DOWNED)


func _on_revived(_new_health: int) -> void:
	hurtbox.active = true
	state_machine.transition_to(State.IDLE)
