extends GutTest

## El acuse de carga, con host y cliente ENet de verdad.
##
## Este archivo existe porque el fallo que arregla NO se ve en localhost ni en un
## test offline: el host emitía los spawns un frame después de dar la partida por
## empezada, confiando en que el cliente ya habría cargado. Con latencia real el
## cliente entraba SIN NINGÚN PERSONAJE — los spawns del `MultiplayerSpawner` son
## de una sola vez y no se reintentan.
##
## Se montan dos `MultiplayerAPI` en un mismo proceso, cada una bajo su raíz, y
## dos `NetworkManager` sueltos (no el autoload) para poder tenerlos por
## duplicado. Los RPC se resuelven por ruta relativa a la raíz de cada API, así
## que ambos se ven como "NetworkManager".

## Los contadores van en `Array` a propósito: GDScript captura las variables
## locales POR VALOR en una lambda, así que un `int` capturado se queda a cero y
## los tests que esperan cero pasan sin comprobar nada.
const ManagerScript := preload("res://autoloads/network_manager.gd")
const PUERTO := 47411

var host_root: Node
var client_root: Node
var host_net: Node
var client_net: Node


func before_each() -> void:
	host_root = Node.new()
	host_root.name = "HostSide"
	client_root = Node.new()
	client_root.name = "ClientSide"
	add_child_autofree(host_root)
	add_child_autofree(client_root)

	var host_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(host_api, host_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())

	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(PUERTO, 1), OK, "hace falta el puerto libre")
	host_api.multiplayer_peer = server_peer

	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", PUERTO), OK)
	client_api.multiplayer_peer = client_peer

	host_net = ManagerScript.new()
	host_net.name = "NetworkManager"
	host_root.add_child(host_net)
	client_net = ManagerScript.new()
	client_net.name = "NetworkManager"
	client_root.add_child(client_net)
	# Se saltan `host()`/`join()`: crearían sus propios peers sobre el
	# `multiplayer` del árbol principal. Aquí la sesión ya está montada a mano.
	host_net.is_active = true
	host_net.is_host_mode = true
	client_net.is_active = true

	await _esperar_conexion()


func after_each() -> void:
	get_tree().set_multiplayer(SceneMultiplayer.new(), host_root.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), client_root.get_path())
	await wait_physics_frames(2)


func _esperar_conexion(max_frames: int = 300) -> void:
	for _i in range(max_frames):
		await wait_physics_frames(1)
		if client_root.multiplayer.get_peers().size() > 0 \
				and host_root.multiplayer.get_peers().size() > 0:
			return


func test_la_conexion_de_prueba_se_establece() -> void:
	# Si esto falla, los demás tests de este archivo no prueban nada.
	assert_eq(host_root.multiplayer.get_unique_id(), 1, "el host es el peer 1")
	assert_eq(client_root.multiplayer.get_peers(), PackedInt32Array([1]),
			"el cliente ve al host")


func test_el_host_solo_no_completa_el_acuse() -> void:
	# El caso que provocaba el fallo: el host daba por hecho que el otro extremo
	# estaba listo.
	var avisos := [0]
	host_net.all_peers_ready.connect(func() -> void: avisos[0] += 1)

	host_net.report_scene_ready()
	await wait_physics_frames(30)

	assert_eq(avisos[0], 0,
			"con el cliente sin acusar, el host NO puede empezar a replicar")


func test_cuando_ambos_acusan_los_dos_reciben_la_señal() -> void:
	var avisos_host := [0]
	var avisos_cliente := [0]
	host_net.all_peers_ready.connect(func() -> void: avisos_host[0] += 1)
	client_net.all_peers_ready.connect(func() -> void: avisos_cliente[0] += 1)

	host_net.report_scene_ready()
	client_net.report_scene_ready()
	await wait_physics_frames(60)

	assert_eq(avisos_host[0], 1, "el host arranca cuando el cliente ya está")
	assert_eq(avisos_cliente[0], 1, "y el cliente se entera también")


func test_el_orden_de_los_acuses_da_igual() -> void:
	# El cliente puede acusar antes de que el host haya montado lo suyo.
	var avisos_host := [0]
	host_net.all_peers_ready.connect(func() -> void: avisos_host[0] += 1)

	client_net.report_scene_ready()
	await wait_physics_frames(20)
	assert_eq(avisos_host[0], 0, "todavía falta el host")

	host_net.report_scene_ready()
	await wait_physics_frames(40)
	assert_eq(avisos_host[0], 1, "acusado el último, se completa igual")


func test_el_host_repitiendose_no_completa_el_acuse_el_solo() -> void:
	# Con una lista en vez de un conjunto, dos acuses del mismo peer bastarían
	# para dar la ronda por buena y volvería el fallo original.
	var avisos := [0]
	host_net.all_peers_ready.connect(func() -> void: avisos[0] += 1)

	host_net.report_scene_ready()
	host_net.report_scene_ready()
	host_net.report_scene_ready()
	await wait_physics_frames(30)

	assert_eq(avisos[0], 0, "tres acuses del host no son el acuse del cliente")


func test_una_segunda_ronda_vuelve_a_funcionar() -> void:
	# El mismo mecanismo sirve para el arranque y para cada carga posterior, así
	# que la ronda tiene que quedar limpia al cerrarse.
	var avisos := [0]
	host_net.all_peers_ready.connect(func() -> void: avisos[0] += 1)

	host_net.report_scene_ready()
	client_net.report_scene_ready()
	await wait_physics_frames(60)
	assert_eq(avisos[0], 1, "primera ronda")

	host_net.report_scene_ready()
	client_net.report_scene_ready()
	await wait_physics_frames(60)
	assert_eq(avisos[0], 2, "segunda ronda, con el conjunto ya vaciado")


func test_sin_sesion_de_red_el_acuse_contesta_en_el_acto() -> void:
	# Abrir `world.tscn` a pelo no puede quedarse esperando a nadie. Se mira
	# `is_active` y no `has_multiplayer_peer()`, que devuelve `true` aun sin
	# sesión porque Godot instala un `OfflineMultiplayerPeer`.
	var suelto := ManagerScript.new()
	add_child_autofree(suelto)
	suelto.is_active = false
	var avisos := [0]
	suelto.all_peers_ready.connect(func() -> void: avisos[0] += 1)

	suelto.report_scene_ready()
	assert_eq(avisos[0], 1, "sin sesión no hay a quién esperar")
