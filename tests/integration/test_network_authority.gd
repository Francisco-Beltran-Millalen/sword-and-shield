extends GutTest

## Qué pasa cuando la sesión de red NO está: al cerrarla, y con una entidad cuyo
## dueño no existe.
##
## Los dos casos vienen del mismo sitio. El código preguntaba "¿hay red?" con
## `multiplayer.has_multiplayer_peer()` en doce puntos, y esa pregunta no
## distinguía nada: sin sesión Godot deja puesto un `OfflineMultiplayerPeer` y
## devuelve `true` igual. Lo único que hacía el guardia era tapar la ventana que
## abría `NetworkManager.reset()` al dejar el árbol SIN peer, donde preguntar por
## la autoridad es un error de motor. Ahora `reset()` no abre esa ventana, y
## estos tests son los que impiden que vuelva a abrirse.
##
## GUT convierte los errores de motor en fallos, así que varios de estos casos se
## caen solos si la regresión vuelve, incluso antes de mirar sus `assert`.

const ManagerScript := preload("res://autoloads/network_manager.gd")
const HurtboxScript := preload("res://components/hurtbox.gd")
const HitboxScript := preload("res://components/hitbox.gd")
const HealthScript := preload("res://components/health_component.gd")
const ReceiverScript := preload("res://components/combat/damage_receiver.gd")

## Un peer que no está en ninguna sesión. Encaminarle un golpe sería un
## `rpc_id` a un id desconocido.
const PEER_FANTASMA := 778899
const PUERTO := 47413

var _raiz: Node
var _net: Node


## El `NetworkManager` va suelto y bajo su propia raíz, con su propia
## `MultiplayerAPI`: `reset()` toca el peer del árbol donde vive, y el del árbol
## principal lo comparte toda la suite.
func before_each() -> void:
	_raiz = Node.new()
	_raiz.name = "SesionDePrueba"
	add_child_autofree(_raiz)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _raiz.get_path())

	_net = ManagerScript.new()
	_net.name = "NetworkManager"
	_raiz.add_child(_net)


func after_each() -> void:
	get_tree().set_multiplayer(SceneMultiplayer.new(), _raiz.get_path())
	await wait_physics_frames(1)


func test_reset_deja_siempre_un_peer_asignado() -> void:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_server(PUERTO, 1), OK, "hace falta el puerto libre")
	_raiz.multiplayer.multiplayer_peer = peer
	_net.is_active = true

	_net.reset()

	assert_true(_raiz.multiplayer.has_multiplayer_peer(),
			"tras reset() sigue habiendo peer: sin él, preguntar por la autoridad "
			+ "es un error de motor durante los frames que quedan hasta el lobby")
	assert_eq(_raiz.multiplayer.get_unique_id(), 1,
			"el peer restaurado es el offline, que se identifica como el 1")
	assert_true(_raiz.multiplayer.is_server(), "y offline uno es su propio servidor")
	assert_false(_net.is_active, "la sesión sí queda cerrada")


func test_tras_reset_un_nodo_propio_sigue_teniendo_su_autoridad() -> void:
	var sonda := Node.new()
	_raiz.add_child(sonda)
	autofree(sonda)

	_net.is_active = true
	_net.reset()

	# Dentro del árbol a propósito: `is_multiplayer_authority()` sobre un nodo
	# fuera de él también es un error de motor, y ese no lo arregla el reset.
	assert_true(sonda.is_inside_tree())
	assert_true(sonda.is_multiplayer_authority(),
			"con el peer offline restaurado, la autoridad por defecto (1) vuelve a "
			+ "ser la de este peer: es lo que permite quitar el guardia de los doce sitios")

	sonda.set_multiplayer_authority(PEER_FANTASMA)
	assert_false(sonda.is_multiplayer_authority(),
			"y un nodo de otro peer contesta que no, sin reventar")


func test_tras_cerrar_la_sesion_se_puede_volver_a_hospedar() -> void:
	# Salir al lobby y hospedar otra vez, en el mismo proceso. Funciona porque el
	# `ENetMultiplayerPeer` es `RefCounted` y `reset()` suelta su última
	# referencia: al liberarse cierra el socket. Medido — lo que cierra el puerto
	# es eso, no asignar `null` antes. Si alguien guardara el peer en un campo del
	# `NetworkManager` "para tenerlo a mano", el puerto quedaría cogido y este test
	# se caería con ERR_CANT_CREATE.
	assert_eq(_hospedar(PUERTO), OK, "hace falta el puerto libre")
	_net.reset()
	await wait_physics_frames(2)

	assert_eq(_hospedar(PUERTO), OK,
			"el socket tiene que quedar libre para volver a hospedar")
	_net.reset()


## Hospeda sin dejar viva ninguna referencia al peer fuera de la `MultiplayerAPI`
## — que es justo lo que hace `host()`, y de lo que depende el test de arriba.
func _hospedar(puerto: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(puerto, 1)
	if error != OK:
		return error
	_raiz.multiplayer.multiplayer_peer = peer
	_net.is_active = true
	return OK


func test_un_golpe_a_una_entidad_sin_dueno_no_se_encamina() -> void:
	var victima := _montar_victima()
	add_child_autofree(victima)
	await get_tree().process_frame

	var salud := victima.get_node("HealthComponent") as HealthComponent
	var hurtbox := victima.get_node("Hurtbox") as Hurtbox
	var antes := salud.current_health

	# La víctima es de un peer que no está en la sesión. Este peer ve el golpe
	# pero no manda sobre ella, así que intentaría encaminárselo a su dueño.
	victima.set_multiplayer_authority(PEER_FANTASMA)

	var hitbox := _montar_hitbox()
	add_child_autofree(hitbox)
	await get_tree().process_frame

	hurtbox.receive(hitbox, hurtbox.global_position)
	await get_tree().process_frame

	# Si el `rpc_id` se intentara, el motor diría "Attempt to call RPC with
	# unknown peer ID" y GUT tumbaría este test por error inesperado.
	assert_eq(salud.current_health, antes,
			"el golpe se descarta: quien manda sobre esta víctima no está para aplicarlo")


func test_un_golpe_a_una_entidad_propia_si_se_aplica() -> void:
	# El contraste del caso anterior: sin él, un receptor que descartara TODOS los
	# golpes pasaría aquel test sin hacer nada.
	var victima := _montar_victima()
	add_child_autofree(victima)
	await get_tree().process_frame

	var salud := victima.get_node("HealthComponent") as HealthComponent
	var hurtbox := victima.get_node("Hurtbox") as Hurtbox
	var antes := salud.current_health

	var hitbox := _montar_hitbox()
	add_child_autofree(hitbox)
	await get_tree().process_frame

	hurtbox.receive(hitbox, hurtbox.global_position)
	await get_tree().process_frame

	assert_lt(salud.current_health, antes,
			"sobre la entidad propia el daño se resuelve aquí mismo")


## Una víctima que no es un `Player`: salud, hurtbox y receptor y nada más.
func _montar_victima() -> Node2D:
	var cuerpo := Node2D.new()
	cuerpo.name = "Victima"

	var salud := HealthScript.new() as HealthComponent
	salud.name = "HealthComponent"
	salud.max_health = 10
	salud.invulnerability_seconds = 0.0
	cuerpo.add_child(salud)

	var hurtbox := HurtboxScript.new() as Hurtbox
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = 0
	hurtbox.health_component = salud
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	forma.shape = rect
	hurtbox.add_child(forma)
	cuerpo.add_child(hurtbox)

	var receptor := ReceiverScript.new() as DamageReceiver
	receptor.name = "DamageReceiver"
	receptor.hurtbox = hurtbox
	receptor.health = salud
	cuerpo.add_child(receptor)

	return cuerpo


func _montar_hitbox() -> Hitbox:
	var hitbox := HitboxScript.new() as Hitbox
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = 0
	hitbox.damage = 3
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	forma.shape = rect
	hitbox.add_child(forma)
	return hitbox
