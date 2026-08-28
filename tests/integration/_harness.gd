class_name IntegrationHarness
extends Node

## Escena determinista con dos jugadores para tests de integración.
##
## Portado del proyecto Tension, que demostró que poder probar el cooperativo
## sin abrir el juego vale su peso en oro. Uso:
##
##     const Harness := preload("res://tests/integration/_harness.gd")
##     var h: IntegrationHarness
##
##     func before_each() -> void:
##         h = IntegrationHarness.new()
##         add_child(h)
##         h.setup()
##
##     func after_each() -> void:
##         h.teardown()
##
## El `IntentSource` de cada jugador se sustituye por un `ScriptedIntentSource`
## ANTES de entrar en el árbol, para que el `@onready` resuelva al doble.

const PlayerScene := preload("res://characters/player/player.tscn")
const SwordKitScene := preload("res://characters/player/kits/sword_kit.tscn")
const ShieldKitScene := preload("res://characters/player/kits/shield_kit.tscn")
const ScriptedSource := preload("res://tests/integration/scripted_intent_source.gd")

const DEFAULT_SPAWN_A := Vector2(-80.0, 0.0)
const DEFAULT_SPAWN_B := Vector2(80.0, 0.0)
const FLOOR_WIDTH := 2000.0

var sword_player: Player
var shield_player: Player
var sword_input: ScriptedIntentSource
var shield_input: ScriptedIntentSource
var floor_body: StaticBody2D


func setup(spawn_a: Vector2 = DEFAULT_SPAWN_A, spawn_b: Vector2 = DEFAULT_SPAWN_B,
		with_floor: bool = true, floor_y: float = 40.0) -> void:
	if with_floor:
		_build_floor(floor_y)

	sword_player = _build_player(0, "Espada", SwordKitScene)
	shield_player = _build_player(1, "Escudo", ShieldKitScene)

	add_child(sword_player)
	add_child(shield_player)

	sword_player.global_position = spawn_a
	shield_player.global_position = spawn_b

	sword_input = sword_player.get_node("IntentSource") as ScriptedIntentSource
	shield_input = shield_player.get_node("IntentSource") as ScriptedIntentSource

	sword_player.equip_kit(SwordKitScene)
	shield_player.equip_kit(ShieldKitScene)


func teardown() -> void:
	for node in [sword_player, shield_player, floor_body]:
		if is_instance_valid(node):
			node.queue_free()
	queue_free()


## Avanza `frames` pasos de física. Godot no expone un "tick manual", así que se
## espera la señal real del árbol: el test corre a la misma cadencia que el juego.
func tick_physics(frames: int = 1) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


## Deja caer a ambos jugadores hasta que toquen suelo (o se agote el margen).
func settle_on_floor(max_frames: int = 120) -> void:
	for _i in range(max_frames):
		await get_tree().physics_frame
		if sword_player.is_on_floor() and shield_player.is_on_floor():
			return


func _build_player(index: int, label: String, _kit: PackedScene) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.player_index = index
	player.display_name = label

	# Cambiar la fuente de intent ANTES de entrar en el árbol: así el @onready
	# del Player resuelve directamente al doble de test.
	var original := player.get_node("IntentSource")
	var scripted := ScriptedSource.new()
	scripted.name = "IntentSource"
	original.name = "IntentSourceRetired"
	player.remove_child(original)
	original.queue_free()
	player.add_child(scripted)
	scripted.owner = player

	return player


func _build_floor(floor_y: float) -> void:
	floor_body = StaticBody2D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(FLOOR_WIDTH, 40.0)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.global_position = Vector2(0.0, floor_y + 20.0)
	add_child(floor_body)
