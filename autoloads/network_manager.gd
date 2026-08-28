extends Node

## Sesión ENet para dos jugadores: hospedar, unirse, desconectar.
##
## Portado del proyecto Tension. Conserva intactas las tres correcciones que
## costaron depuración allí (ver comentarios en línea): el pestillo contra el
## doble cambio de escena, la espera de un frame antes de que el host cargue, y
## la desconexión que espera un frame para que los RPC en vuelo se entreguen.
##
## Diferencia con el original: este nodo **no conoce ninguna ruta de escena**.
## Antes hacía `change_scene_to_file("res://systems/lobby/lobby.tscn")` en tres
## sitios, lo que lo ataba al flujo de aquel juego. Ahora solo emite señales;
## quien escuche decide qué escena cargar (§3 de la constitución).

## La partida puede empezar: todos los peers han de cargar la escena de juego.
signal game_ready(is_host: bool)
## La sesión terminó (desconexión, caída del host, salida voluntaria).
signal session_ended(reason: String)
## No se pudo establecer la conexión.
signal connection_error(message: String)

const DEFAULT_PORT: int = 4242
## Estrictamente dos jugadores: host + un peer.
const MAX_PEERS: int = 1

var is_host_mode: bool = false
var is_active: bool = false
var port: int = DEFAULT_PORT

var _last_join_ip: String = ""
## Se echa el pestillo en cuanto se emite el arranque de partida. Un
## `peer_connected` duplicado o tardío (habitual cuando un cliente ya estaba
## intentando conectar antes de que el host existiera) no debe disparar un
## SEGUNDO arranque: dos cambios de escena seguidos son un cierre en seco.
var _game_started: bool = false


func host(p_port: int = DEFAULT_PORT) -> Error:
	reset()
	port = p_port

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PEERS)
	if error != OK:
		return error

	is_active = true
	is_host_mode = true
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join(ip: String, p_port: int = DEFAULT_PORT) -> Error:
	reset()
	port = p_port

	_last_join_ip = ip.strip_edges()
	if _last_join_ip.is_empty():
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(_last_join_ip, port)
	if error != OK:
		return error

	is_active = true
	is_host_mode = false
	multiplayer.multiplayer_peer = peer
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func reset() -> void:
	_disconnect_signals()
	multiplayer.multiplayer_peer = null
	is_active = false
	is_host_mode = false
	_game_started = false
	_last_join_ip = ""


## Cierra la sesión y avisa. Quien escuche `session_ended` decide a qué escena ir.
func leave(reason: String = "salida voluntaria") -> void:
	if not is_active:
		return
	reset()
	# Un frame de margen para que los RPC ya decodificados por el motor en este
	# frame se entreguen a nodos todavía válidos antes de que cambie el árbol.
	await get_tree().process_frame
	session_ended.emit(reason)


func _on_peer_connected(id: int) -> void:
	if _game_started:
		push_warning("[NET] se ignora peer_connected extra id=%d (la partida ya arranca)" % id)
		return
	_game_started = true
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	# Difusión a todos los peers (incluido el propio host, por `call_local`) para
	# que ambos carguen la escena a la vez. Cargar nodos replicados antes de que
	# el cliente tenga la escena lista provoca desincronización.
	_start_game.rpc()


func _on_peer_disconnected(_id: int) -> void:
	_end_session("el otro jugador se desconectó")


func _on_server_disconnected() -> void:
	_end_session("se perdió la conexión con el host")


func _on_connection_failed() -> void:
	var failed_ip := _last_join_ip
	reset()
	connection_error.emit("No se pudo conectar a %s:%d." % [failed_ip, port])


func _end_session(reason: String) -> void:
	push_warning("[NET] %s" % reason)
	reset()
	await get_tree().process_frame
	session_ended.emit(reason)


func _disconnect_signals() -> void:
	for pair in [
		[multiplayer.peer_connected, _on_peer_connected],
		[multiplayer.peer_disconnected, _on_peer_disconnected],
		[multiplayer.connection_failed, _on_connection_failed],
		[multiplayer.server_disconnected, _on_server_disconnected],
	]:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		if sig.is_connected(callable):
			sig.disconnect(callable)


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	if multiplayer.is_server():
		# El cliente recibe este RPC y encola su carga de escena ANTES de que el
		# host cargue la suya. Así el cliente ya tiene la escena en el árbol
		# cuando los MultiplayerSynchronizer del host registran su caché de rutas.
		await get_tree().process_frame
	game_ready.emit(multiplayer.is_server())
