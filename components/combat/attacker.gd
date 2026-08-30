class_name Attacker
extends Node

## Ejecuta ataques: reproduce su animación y abre la ventana de daño cuando la
## propia animación lo dice.
##
## **No sabe quién es su dueño.** No comprueba tipos, no busca a su padre, no
## conoce `Player` ni ningún kit. Un jugador, un enemigo, un jefe o una trampa
## con partes móviles lo usan igual: se le asignan un `AnimationPlayer`, una
## `Hitbox` y una lista de `AttackData`, y se le pide `attack()`.
##
## La ventana activa la abren y cierran **pistas de método de la animación**
## llamando a `open_window()` / `close_window()` de este nodo (§13). Por eso las
## animaciones no necesitan saber dónde está la hitbox: hablan con el atacante,
## y él sabe cuál es la suya. Una misma biblioteca de animaciones sirve para
## entidades con estructuras de escena distintas.
##
## Nada de contadores de frames en GDScript: el *cuándo* es del
## `AnimationPlayer`, el *qué* es del `AttackData`.

const ComponentLookup := preload("res://components/component_lookup.gd")

## Empezó un ataque. `index` es su posición en `attacks`.
signal attack_started(data: AttackData, index: int)
## Terminó el ataque (encadene o no).
signal attack_finished(data: AttackData)
## La cadena terminó y el atacante vuelve a estar libre.
signal chain_ended
## La hitbox conectó. Se reenvía aquí para que el dueño no tenga que conocerla.
signal hit_landed(hurtbox: Hurtbox, hit_position: Vector2, data: AttackData)
## El golpe fue bloqueado por una guardia.
signal hit_guarded(guard: GuardBox, hit_position: Vector2, data: AttackData)
## El ataque pide desplazar al dueño. Quien lo reciba decide si lo aplica (§2).
signal lunge_requested(impulse: Vector2)

## Repertorio, en orden de encadenado.
@export var attacks: Array[AttackData] = []
## Quién reproduce las animaciones. Si se deja vacío se busca por nombre entre
## los hermanos y, si no aparece, por tipo bajo la entidad.
@export var animation_player: AnimationPlayer
## Qué volumen inflige el daño. Misma búsqueda que arriba. Asignarlo a mano
## solo hace falta si la entidad tiene más de una hitbox.
@export var hitbox: Hitbox

var _index: int = 0
var _chain_queued: bool = false
var _busy: bool = false
## Hacia dónde miraba quien pidió el ataque. Se guarda porque los golpes
## encadenados no vuelven a preguntarlo: sin esto el segundo y el tercero
## arremetían siempre a la derecha.
var _facing: int = 1


func _ready() -> void:
	if animation_player == null:
		animation_player = _find_component("AnimationPlayer", "AnimationPlayer") as AnimationPlayer
	if hitbox == null:
		hitbox = _find_component("Hitbox", "Hitbox") as Hitbox

	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	if hitbox != null:
		hitbox.hit.connect(_on_hit)
		hitbox.guarded.connect(_on_guarded)


## ¿Hay un ataque en curso?
func is_attacking() -> bool:
	return _busy


## El ataque en curso, o `null`.
func current_attack() -> AttackData:
	if _index < 0 or _index >= attacks.size():
		return null
	return attacks[_index]


## Pide atacar. Si ya hay uno en curso y ese ataque encadena, encola el
## siguiente; si no, se ignora. `facing` orienta el golpe (-1 / 1).
func attack(facing: int = 1) -> void:
	if attacks.is_empty():
		return
	if _busy:
		var data := current_attack()
		if data != null and data.chains:
			_chain_queued = true
		return
	_start(facing)


## Corta el ataque en curso: daño recibido, aturdimiento, cambio de estado.
func interrupt() -> void:
	_chain_queued = false
	_index = 0
	_busy = false
	close_window()
	if animation_player != null and animation_player.is_playing():
		animation_player.stop()


## --- Llamadas desde las pistas de método de la animación ---

## Abre la ventana de daño. La llama la animación en su primer frame activo.
func open_window() -> void:
	var data := current_attack()
	if hitbox == null or data == null:
		return
	hitbox.damage = data.damage
	hitbox.knockback = data.knockback
	hitbox.attack_id = data.attack_id
	hitbox.max_targets = data.max_targets
	hitbox.enable()


## Cierra la ventana de daño. La llama la animación al acabar los frames activos.
func close_window() -> void:
	if hitbox != null:
		hitbox.disable()


func _start(facing: int) -> void:
	_busy = true
	_chain_queued = false
	_facing = signi(facing) if facing != 0 else 1
	var data := current_attack()
	if data == null:
		_busy = false
		return

	if data.lunge_speed > 0.0:
		lunge_requested.emit(Vector2(float(_facing) * data.lunge_speed, 0.0))

	attack_started.emit(data, _index)

	if animation_player != null and animation_player.has_animation(data.animation):
		animation_player.play(data.animation)
	else:
		# Sin animación asignada todavía (arte pendiente): el atacante no se
		# queda colgado, pero se avisa porque la ventana de daño nunca se abrirá.
		push_warning("Attacker: falta la animación '%s'; el golpe no hará daño." % data.animation)
		_finish()


func _finish() -> void:
	close_window()
	var data := current_attack()
	if data != null:
		attack_finished.emit(data)

	if _chain_queued and _index + 1 < attacks.size():
		_chain_queued = false
		_index += 1
		_start(_facing)
		return

	_chain_queued = false
	_index = 0
	_busy = false
	chain_ended.emit()


## Busca una pieza de la entidad. La búsqueda vive en `ComponentLookup` porque
## es la misma que hacen `DamageReceiver` y `Hurtbox`, y las tres copias habían
## divergido.
func _find_component(node_name: String, type_name: String) -> Node:
	return ComponentLookup.find(get_parent(), node_name, type_name)


func _on_animation_finished(_anim: StringName) -> void:
	if _busy:
		_finish()


## Un golpe que conecta se anuncia dos veces y no es redundante: la señal local
## es para el dueño (el kit, el enemigo), y el bus es para quien no puede
## conocerlo — el hit-stop, el temblor de pantalla, el audio.
##
## Se emite AQUÍ y no en cada dueño a propósito. Mientras lo hacía solo el
## `SwordKit`, el enemigo reutilizaba este mismo `Attacker` y sus golpes no
## llegaban al bus: el día que hubiera hit-stop, la espada sacudiría la cámara y
## la garra no. Un emisor en vez de uno por entidad, y cualquier cosa que use un
## `Attacker` —una trampa, un jefe— queda cubierta sin escribir nada.
##
## Sí, esto ata un componente reutilizable a un autoload. Las tres condiciones de
## admisión de `GameEvents` se cumplen —emisor y receptor no pueden conocerse por
## el árbol, sobrevive a las transiciones, y admite cero receptores—, que es
## justo el caso para el que ese bus existe.
func _on_hit(hurtbox: Hurtbox, hit_position: Vector2) -> void:
	var data := current_attack()
	hit_landed.emit(hurtbox, hit_position, data)
	# Cada volumen resuelve su propia entidad: el atacante no es la hitbox y la
	# víctima no es la hurtbox.
	var origen: Node = hitbox.attacker() if hitbox != null else null
	GameEvents.hit_landed.emit(origen, hurtbox.entity(), data.damage if data != null else 0)


func _on_guarded(guard: GuardBox, hit_position: Vector2) -> void:
	hit_guarded.emit(guard, hit_position, current_attack())
