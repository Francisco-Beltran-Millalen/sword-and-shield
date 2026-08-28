extends Node2D

## Escena de juego provisional: hace aparecer a los dos personajes y se aparta.
##
## La aparición la hace un `MultiplayerSpawner` del motor, no un bucle propio
## de instanciación (§13). El host crea los personajes bajo `$Players` y el
## spawner los replica; cada cliente recibe los dos, pero solo simula y enmarca
## el suyo —esa decisión vive dentro del propio `Player`, no aquí.
##
## Provisional: esto lo sustituirá el sistema de salas. Lo que sí es definitivo
## es la forma —el coordinador no cablea el juego, solo coloca.

const PlayerScene := preload("res://characters/player/player.tscn")

@onready var players_root: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawns: Node2D = $Spawns


const LOBBY_SCENE := "res://systems/network/lobby.tscn"


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	GameEvents.player_downed.connect(_on_player_downed)
	# Si la sesión cae (el otro jugador se va, se pierde la conexión), esta
	# escena no tiene sentido: se vuelve al lobby. El `NetworkManager` solo
	# avisa; quien decide la escena es este nodo (§3).
	NetworkManager.session_ended.connect(_on_session_ended)

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_spawn_all()


func _on_session_ended(_reason: String) -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		NetworkManager.leave()
		get_viewport().set_input_as_handled()


## El host crea un personaje por peer. `spawn()` replica la creación a todos.
func _spawn_all() -> void:
	var peers: Array[int] = [1]
	if multiplayer.has_multiplayer_peer():
		for peer in multiplayer.get_peers():
			peers.append(peer)

	for index in range(peers.size()):
		spawner.spawn({"peer": peers[index], "index": index})


## La ejecuta el spawner en TODOS los peers, con los datos que envió el host.
func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info.get("peer", 1)
	var index: int = info.get("index", 0)

	var player := PlayerScene.instantiate() as Player
	player.name = "Player_%d" % peer_id
	player.player_index = index
	player.display_name = SessionState.kit_name_for(peer_id)
	player.set_owning_peer(peer_id)
	player.equip_kit(SessionState.kit_scene_for(peer_id))

	var spawn := spawns.get_node_or_null("Spawn%d" % (index + 1)) as Marker2D
	if spawn != null:
		player.position = spawn.position
	return player


func _on_player_downed(player_index: int) -> void:
	# Provisional: reaparecer donde estaba. El sistema de puntos de guardado
	# llega con la progresión.
	var timer := get_tree().create_timer(1.5)
	await timer.timeout
	for child in players_root.get_children():
		var player := child as Player
		if player != null and player.player_index == player_index:
			player.revive_full()
			return
