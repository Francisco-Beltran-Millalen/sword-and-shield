class_name Player
extends CharacterBody2D

## El jugador: un orquestador delgado sobre componentes.
##
## Deliberadamente pequeño. Su antecesor en el proyecto Tension llegó a 1.000
## líneas porque acumuló el estado de seis capacidades, once métodos del sistema
## de cuerda y una API pública que era, en su mayoría, superficie de otros
## sistemas. Aquí cada responsabilidad vive en un hijo y el Player solo reparte
## el frame (§1: llama hacia abajo, señaliza hacia arriba).
##
## Regla para mantenerlo así: si vas a añadir una variable de estado que
## pertenece a una capacidad, va en el kit, no aquí (§2, enmienda de capacidades).

signal state_changed(new_state: State)
signal health_changed(current: int, maximum: int)
signal facing_changed(facing: int)

enum State {
	IDLE,
	RUN,
	JUMP,
	FALL,
	KIT_ACTION,   ## El kit se adueñó del control (ataque, guardia).
	HURT,
	DOWNED,
}

@export_range(0, 1) var player_index: int = 0
@export var display_name: String = "P1"

@onready var stats: StatsComponent = $StatsComponent
@onready var health: HealthComponent = $HealthComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var locomotion: Locomotion = $Locomotion
@onready var intent_source: IntentSource = $IntentSource
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visuals: Node2D = $Visuals

var kit: PlayerKit
var _facing: int = 1
var _pending_impulse: Vector2 = Vector2.ZERO

## Estado replicable. Un único entero en vez de las catorce propiedades que
## sincronizaba el proyecto anterior; el combate viajará como eventos, no como
## estado por frame.
var replicated_state: int:
	get: return state_machine.current_state if state_machine != null else State.IDLE
	set(value):
		if state_machine != null:
			state_machine.replicated_state = value


func _ready() -> void:
	_setup_states()
	health.health_changed.connect(_on_health_changed)
	health.depleted.connect(_on_depleted)
	health.revived.connect(_on_revived)
	hurtbox.wounded.connect(_on_wounded)
	_bind_kit()


func _physics_process(delta: float) -> void:
	var intent := intent_source.poll()

	if state_machine.is_in(State.DOWNED):
		velocity.x = move_toward(velocity.x, 0.0, stats.get_stat(StatsComponent.StatID.FRICTION) * delta)
		move_and_slide()
		return

	_update_facing(intent)

	if kit != null:
		if intent.attack_pressed:
			kit.on_action_pressed(self, intent)
		kit.tick(self, intent, delta)

	if _pending_impulse != Vector2.ZERO:
		velocity += _pending_impulse
		_pending_impulse = Vector2.ZERO

	var speed_scale := 1.0
	if kit != null and kit.has_method("speed_scale"):
		speed_scale = kit.speed_scale()

	locomotion.tick(self, stats, intent, delta, speed_scale)
	_settle_state()


## Dirección a la que mira, -1 o 1. La consultan los kits.
func get_facing() -> int:
	return _facing


## Único camino para que algo externo mueva a este jugador (§2). Los kits lo
## alcanzan por señal; los sistemas del mundo, llamando a este método.
func apply_impulse(impulse: Vector2) -> void:
	if stats.get_stat_bool(StatsComponent.StatID.IS_IMMOVABLE):
		return
	_pending_impulse += impulse


## Coloca al jugador en un punto y limpia el movimiento. Lo usan las
## transiciones de sala y los reapariciones.
func place_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	locomotion.reset()


func revive_full() -> void:
	health.revive()
	locomotion.reset()


func _setup_states() -> void:
	if state_machine.current_state == StateMachine.STATE_UNDEFINED:
		state_machine.init_state(State.IDLE)
	state_machine.set_state_name(State.IDLE, "IDLE")
	state_machine.set_state_name(State.RUN, "RUN")
	state_machine.set_state_name(State.JUMP, "JUMP")
	state_machine.set_state_name(State.FALL, "FALL")
	state_machine.set_state_name(State.KIT_ACTION, "KIT_ACTION")
	state_machine.set_state_name(State.HURT, "HURT")
	state_machine.set_state_name(State.DOWNED, "DOWNED")
	state_machine.state_changed.connect(func(_from: int, to: int) -> void: state_changed.emit(to))


## Instala el kit de este jugador. Se llama al aparecer, no se hornea en la
## escena: el reparto (quién lleva espada y quién escudo) es una decisión de
## sesión, y así el mismo `player.tscn` sirve para ambos.
## Reemplaza el kit anterior si lo hubiera.
func equip_kit(kit_scene: PackedScene) -> void:
	if kit_scene == null:
		return
	var previous := get_node_or_null("Kit")
	if previous != null:
		previous.name = "KitRetired"
		previous.queue_free()

	var instance := kit_scene.instantiate() as PlayerKit
	if instance == null:
		push_error("equip_kit: la escena no tiene raíz PlayerKit.")
		return
	instance.name = "Kit"
	add_child(instance)
	_bind_kit()


func _bind_kit() -> void:
	kit = get_node_or_null("Kit") as PlayerKit
	if kit == null:
		return
	if not kit.impulse_requested.is_connected(apply_impulse):
		kit.impulse_requested.connect(apply_impulse)


func _update_facing(intent: PlayerIntent) -> void:
	var wanted: int = intent.facing()
	if wanted == 0 or wanted == _facing:
		return
	_facing = wanted
	if visuals != null:
		visuals.scale.x = float(_facing)
	facing_changed.emit(_facing)


## Deriva el estado del cuerpo y del kit. Estados pegajosos (HURT, DOWNED) los
## limpian sus propios escritores; aquí solo se resuelve la locomoción.
func _settle_state() -> void:
	if state_machine.is_in(State.DOWNED):
		return

	# El aturdimiento dura lo que duran los i-frames del HealthComponent. Se
	# reutiliza ese temporizador en vez de añadir un contador propio (§13).
	if state_machine.is_in(State.HURT):
		if health.is_invulnerable():
			return
		state_machine.transition_to(State.IDLE)

	if kit != null and kit.is_busy():
		state_machine.transition_to(State.KIT_ACTION)
		return

	if not is_on_floor():
		state_machine.transition_to(State.JUMP if velocity.y < 0.0 else State.FALL)
		return

	state_machine.transition_to(State.IDLE if absf(velocity.x) < 8.0 else State.RUN)


func _on_wounded(hitbox: Hitbox, _hit_position: Vector2) -> void:
	var defense := stats.get_stat(StatsComponent.StatID.DEFENSE)
	var amount := maxi(1, int(round(float(hitbox.damage) * defense)))
	health.take_damage(amount, hitbox.attacker())

	if health.is_dead:
		return

	var push := hitbox.direction_to(self) * hitbox.knockback \
			* stats.get_stat(StatsComponent.StatID.KNOCKBACK_TAKEN)
	apply_impulse(push)
	if kit != null:
		kit.on_interrupted(self)
	state_machine.transition_to(State.HURT)
	GameEvents.hit_landed.emit(hitbox.attacker(), self, amount)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_depleted(_source: Node) -> void:
	if kit != null:
		kit.on_interrupted(self)
	state_machine.transition_to(State.DOWNED)
	GameEvents.player_downed.emit(player_index)


func _on_revived(_new_health: int) -> void:
	state_machine.transition_to(State.IDLE)
