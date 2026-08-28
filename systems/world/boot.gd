extends Node2D

## Escena de arranque provisional: dos jugadores con sus kits sobre una sala de
## prueba, para poder ejecutar el juego desde el primer día.
##
## Provisional a propósito. Aquí es donde entrará el flujo real (menú → sesión →
## sala) en cuanto estén tomadas las decisiones pendientes del README: modelo de
## cámara, sofá o red, y reparto de kits.
##
## Nótese lo que NO hace, a diferencia del `main.gd` del proyecto anterior: no
## cablea el juego con cuarenta `.connect()` ni conoce a cada sistema por su
## `$Ruta`. Coloca a los jugadores, les da su kit y se aparta.

const PlayerScene := preload("res://characters/player/player.tscn")
const SwordKit := preload("res://characters/player/kits/sword_kit.tscn")
const ShieldKit := preload("res://characters/player/kits/shield_kit.tscn")

## Reparto de kits. Fijo por índice hasta que se decida si es intercambiable.
const KIT_BY_INDEX: Array[PackedScene] = [SwordKit, ShieldKit]

@onready var spawns: Node2D = $Spawns
@onready var camera: Camera2D = $Camera2D

var _players: Array[Player] = []


func _ready() -> void:
	for index in range(2):
		_players.append(_spawn_player(index))
	GameEvents.player_downed.connect(_on_player_downed)


func _process(_delta: float) -> void:
	if _players.size() < 2:
		return
	# Encuadre provisional: punto medio de ambos jugadores. El suavizado lo hace
	# la propia Camera2D (`position_smoothing_enabled`), no un lerp a mano (§13).
	var midpoint := (_players[0].global_position + _players[1].global_position) * 0.5
	camera.global_position = midpoint + Vector2(0.0, -60.0)


func _spawn_player(index: int) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.player_index = index
	player.display_name = "P%d" % (index + 1)
	add_child(player)

	var source := player.get_node("IntentSource") as LocalIntentSource
	if source != null:
		source.player_index = index

	player.equip_kit(KIT_BY_INDEX[index])

	var spawn := spawns.get_node_or_null("Spawn%d" % (index + 1)) as Marker2D
	if spawn != null:
		player.place_at(spawn.global_position)
	return player


func _on_player_downed(player_index: int) -> void:
	# Provisional: reaparecer en el sitio tras un momento. El sistema real de
	# puntos de guardado llega con la progresión.
	var timer := get_tree().create_timer(1.5)
	await timer.timeout
	if player_index < _players.size() and is_instance_valid(_players[player_index]):
		_players[player_index].revive_full()
