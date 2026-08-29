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
signal room_changed(room_id: StringName)

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
@onready var damage_receiver: DamageReceiver = $DamageReceiver
@onready var visuals: Node2D = $Visuals
@onready var camera: PlayerCamera = $PlayerCamera

var kit: PlayerKit
## Sala en la que está. La escribe `enter_room`; la leen el guardado y el HUD.
var current_room: StringName = &""
var _facing: int = 1
var _pending_impulse: Vector2 = Vector2.ZERO
## Intent vacío para los estados en los que el jugador no manda (§4: la
## locomoción sigue siendo el único escritor de `velocity`).
var _idle_intent := PlayerIntent.new()

## Estado replicable. Un único entero en vez de las catorce propiedades que
## sincronizaba el proyecto anterior; el combate viajará como eventos, no como
## estado por frame.
var replicated_state: int:
	get: return state_machine.current_state if state_machine != null else State.IDLE
	set(value):
		if state_machine != null:
			state_machine.replicated_state = value

## Encaramiento replicado: sin esto un personaje remoto miraría siempre a la
## derecha. Al llegar, aplica el volteo de los visuales igual que en local.
var replicated_facing: int:
	get: return _facing
	set(value):
		if value == 0 or value == _facing:
			return
		_facing = value
		_apply_facing_visuals()


func _ready() -> void:
	# Lo que hace de este cuerpo un viajero entre zonas es pertenecer al grupo,
	# no ser un `Player`: así `ZoneDoor` no necesita conocer esta clase.
	add_to_group(&"zone_travellers")
	# Quien empuña es el atacante, no el arma: sin esto la hitbox del kit
	# resolvía su `owner`, que es el propio Kit (ver `Hitbox.attacker`).
	add_to_group(&"combat_source")
	_setup_states()
	health.health_changed.connect(_on_health_changed)
	health.depleted.connect(_on_depleted)
	health.revived.connect(_on_revived)
	damage_receiver.damage_taken.connect(_on_damage_taken)
	damage_receiver.knockback_requested.connect(apply_impulse)
	_bind_kit()
	_apply_authority()


## Fija qué peer manda sobre este personaje y enciende lo que corresponda.
## La llama el spawner de la sesión al crear el jugador.
func set_owning_peer(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	if is_node_ready():
		_apply_authority()


## ¿Es este el personaje que controla este cliente?
##
## `is_multiplayer_authority()` a secas responde en los tres casos, sin preguntar
## si hay red: sin sesión, Godot tiene puesto un `OfflineMultiplayerPeer` cuyo
## `get_unique_id()` es 1 y la autoridad por defecto de un nodo es 1, así que el
## único jugador que existe es el suyo. Preguntar antes por
## `has_multiplayer_peer()` era una rama que no se tomaba nunca, y como el
## `NetworkManager` mantiene siempre un peer asignado, tampoco protege ya de
## nada (ver `NetworkManager.reset`).
func is_local_player() -> bool:
	return is_multiplayer_authority()


## Solo el peer con autoridad simula y ve por esta cámara. Los personajes
## remotos apagan su cámara y su lectura de teclado: su posición y su estado
## llegan replicados por el `MultiplayerSynchronizer`.
func _apply_authority() -> void:
	var local := is_local_player()
	if camera != null:
		camera.set_local(local)
	if intent_source != null:
		intent_source.set_process_mode(
			Node.PROCESS_MODE_INHERIT if local else Node.PROCESS_MODE_DISABLED)


func _physics_process(delta: float) -> void:
	# Autoridad por jugador: cada peer simula el suyo y replica el resultado.
	# Un personaje remoto no simula nada — deja que el sincronizador escriba su
	# posición. Esto sustituye por completo al reenvío de intent por RPC del
	# proyecto anterior, que añadía un viaje de ida y vuelta a cada pulsación.
	#
	# El guardia `has_multiplayer_peer()` que había aquí decía protegerse de que
	# "tras una desconexión la escena sigue viva unos frames sin peer". Medido:
	# falso. Cuando el otro extremo cae, el motor no quita el peer —`get_unique_id`
	# sigue devolviendo el id viejo—; el único que lo quitaba era
	# `NetworkManager.reset()`, y ya no lo hace. Sin sesión, la autoridad por
	# defecto es 1 y el `OfflineMultiplayerPeer` también, así que esto se cumple
	# y se simula normal.
	if not is_multiplayer_authority():
		return

	var intent := intent_source.poll()

	if state_machine.is_in(State.DOWNED):
		# Un intent en blanco: se frena y cae, pero no anda ni salta. Antes esto
		# movía el cuerpo a mano, duplicando la locomoción y dejando dos
		# escritores de `velocity` (§4) — y un caído en el aire se quedaba
		# flotando, porque la rama propia no aplicaba gravedad.
		locomotion.tick(self, stats, _idle_intent, delta)
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
	if kit != null:
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


## Entró en una sala: reencuadra la cámara a sus límites. La llama la
## `RoomBounds` correspondiente. Solo surte efecto en el personaje local — el
## remoto lleva la cámara apagada.
func enter_room(room_id: StringName, bounds: Rect2) -> void:
	if room_id == current_room:
		return
	current_room = room_id
	if camera != null:
		camera.apply_room_bounds(bounds)
	room_changed.emit(room_id)


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
	_apply_facing_visuals()


func _apply_facing_visuals() -> void:
	if visuals != null:
		visuals.scale.x = float(_facing)
	if kit != null:
		kit.scale.x = float(_facing)
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


## El daño ya lo calculó y aplicó `DamageReceiver` (defensa, salud, empuje).
## Aquí solo queda la reacción propia del jugador: cortar lo que hiciera el kit
## y entrar en aturdimiento.
func _on_damage_taken(_amount: int, _from: Node, _hit_position: Vector2) -> void:
	if health.is_dead:
		return
	if kit != null:
		kit.on_interrupted(self)
	state_machine.transition_to(State.HURT)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_depleted(_source: Node) -> void:
	if kit != null:
		kit.on_interrupted(self)
	# Sin esto el salto en buffer sobrevive a la muerte y el cuerpo pega un
	# brinco al tocar el suelo.
	locomotion.reset()
	state_machine.transition_to(State.DOWNED)


func _on_revived(_new_health: int) -> void:
	state_machine.transition_to(State.IDLE)
