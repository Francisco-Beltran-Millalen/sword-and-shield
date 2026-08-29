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
## Todos los peers tienen ya montada su escena: se puede empezar a replicar.
signal all_peers_ready()

const DEFAULT_PORT: int = 4242
## Estrictamente dos jugadores: host + un peer.
const MAX_PEERS: int = 1
## Cuánto se espera a que el otro extremo acuse su carga antes de rendirse.
## Generoso a propósito: cubre una carga lenta, no una red lenta.
const READY_TIMEOUT_SECONDS: float = 15.0

# ephemeral: todo el estado de abajo dura lo que la sesión y lo vacía `reset()`.
var is_host_mode: bool = false
var is_active: bool = false
var port: int = DEFAULT_PORT

var _last_join_ip: String = ""
## Quién ha acusado ya su carga en la ronda en curso. Es un conjunto y no una
## lista: con una lista, un peer que reporta dos veces —y puede, si dos cargas
## se solapan— completaría el acuse él solo comparando tamaños, que es
## exactamente el fallo que esto viene a impedir.
var _peers_ready: Dictionary = {}
## Corta la espera si alguien no acusa nunca. Sin esto el otro extremo se queda
## mirando un mundo vacío para siempre y sin un mensaje.
var _ready_timeout: SceneTreeTimer = null
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


## Cierra la sesión y deja el árbol en el estado de arranque.
##
## Restaurar un `OfflineMultiplayerPeer` NO es cosmético: mantiene la invariante
## de que **siempre hay un peer asignado**. Sin ella, entre `reset()` y el cambio
## de escena queda una ventana en la que `get_unique_id()` e
## `is_multiplayer_authority()` son errores de motor —medido: "No multiplayer
## peer is assigned"—, y defenderse de esa ventana obligaba a un guardia
## `has_multiplayer_peer()` repetido en doce sitios. Es el peer que Godot instala
## por defecto al arrancar (§13): con él, `get_unique_id()` vuelve a 1,
## `is_server()` a `true` y los RPC `call_local` siguen entregándose.
##
## El socket ENet lo cierra el propio peer al liberarse —es `RefCounted` y aquí
## se suelta su última referencia—, no el hecho de asignar `null` antes. Medido:
## con o sin ese paso intermedio, el puerto vuelve a estar libre; y si alguien
## guardara el peer en una variable de este nodo, no lo estaría con ninguno de
## los dos. Por eso se asigna directamente y no hay paso intermedio que explicar.
func reset() -> void:
	_disconnect_signals()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_active = false
	is_host_mode = false
	_game_started = false
	_last_join_ip = ""
	_peers_ready.clear()
	_cancel_ready_timeout()


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
	# Antes el host esperaba aquí un `process_frame` confiando en que para
	# entonces el cliente ya habría cargado. Eso solo es cierto si el viaje de
	# ida cabe en 16 ms, o sea en localhost: con latencia de verdad el host
	# hacía aparecer a los jugadores antes de que el cliente tuviera el árbol, y
	# el cliente ENTRABA A LA PARTIDA SIN NINGÚN PERSONAJE —los spawns son de una
	# sola vez y no se reintentan—. Ahora nadie apuesta: se acusa la carga.
	game_ready.emit(multiplayer.is_server())


## --- Acuse de carga ---
##
## Nada replicado —los spawns del `MultiplayerSpawner`, sobre todo— puede salir
## hasta que TODOS los peers tengan su escena montada. Vive aquí y no en el
## `World` por dos razones: es estado de sesión y `reset()` lo limpia (§9), y
## sobre todo un autoload existe en ambos extremos aunque el `World` del otro
## todavía no, que es justo el caso que se está ordenando.


## Este peer ya tiene montada su escena de juego. La llama quien la monta.
##
## Sin sesión de red contesta en el acto. Se pregunta por `is_active`, que es el
## dato del que este nodo es dueño, y no por `has_multiplayer_peer()`: ese
## devuelve `true` aunque no haya red —Godot instala un `OfflineMultiplayerPeer`
## al arrancar— y desde `reset()` lo devuelve siempre, por la invariante de
## arriba. Como pregunta de sesión no distingue nada.
func report_scene_ready() -> void:
	if not is_active:
		all_peers_ready.emit()
		return
	if multiplayer.is_server():
		_register_ready(1)
	else:
		_arm_ready_timeout()
		_rpc_peer_ready.rpc_id(1)


## Lo recibe solo el host. Sin `call_local`: el host se apunta llamando
## directamente, y así el cliente no recibe también el acuse ajeno.
@rpc("any_peer", "reliable")
func _rpc_peer_ready() -> void:
	if not multiplayer.is_server():
		return
	_register_ready(multiplayer.get_remote_sender_id())


func _register_ready(peer_id: int) -> void:
	_peers_ready[peer_id] = true
	_arm_ready_timeout()
	for expected in _expected_peers():
		if not _peers_ready.has(expected):
			return
	# La ronda se cierra y el conjunto queda vacío para la siguiente: el mismo
	# mecanismo sirve para el arranque y para cada carga posterior.
	_peers_ready.clear()
	_cancel_ready_timeout()
	_rpc_all_ready.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_all_ready() -> void:
	_cancel_ready_timeout()
	all_peers_ready.emit()


func _expected_peers() -> Array[int]:
	var expected: Array[int] = [1]
	for peer in multiplayer.get_peers():
		expected.append(peer)
	return expected


func _arm_ready_timeout() -> void:
	_cancel_ready_timeout()
	_ready_timeout = get_tree().create_timer(READY_TIMEOUT_SECONDS)
	_ready_timeout.timeout.connect(_on_ready_timeout)


func _cancel_ready_timeout() -> void:
	if _ready_timeout != null and _ready_timeout.timeout.is_connected(_on_ready_timeout):
		_ready_timeout.timeout.disconnect(_on_ready_timeout)
	_ready_timeout = null


## Rendirse en voz alta es mejor que esperar en silencio: sin esto, un cliente
## que no llega a montar su escena deja al otro mirando un mundo vacío sin un
## solo mensaje, que es el mismo síntoma que este acuse viene a eliminar.
func _on_ready_timeout() -> void:
	_ready_timeout = null
	if not is_active:
		return
	leave("el otro jugador no terminó de cargar la partida")
