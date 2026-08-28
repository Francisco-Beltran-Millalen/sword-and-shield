@tool
class_name ZoneDoor
extends Area2D

## Puerta entre zonas: el único punto de carga real del mundo.
##
## Dentro de una zona no hay carga; cruzar de zona sí la hay. Por eso la puerta
## puede **exigir que ambos jugadores estén dentro** antes de cruzar: convierte
## el caso "cada jugador en una zona distinta" en algo imposible por
## construcción, en vez de en algo que hay que sincronizar bien.
## Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`.

## Se cumplieron las condiciones para cruzar. Lo escucha el `World`.
signal traversal_requested(target_zone: String, target_door: StringName)
## Cambió cuántos jugadores esperan en la puerta. Lo usa el HUD para avisar
## ("esperando a tu compañero").
signal waiting_changed(present: int, required: int)

## Identificador de esta puerta dentro de su zona. La puerta de destino nombra
## a esta para saber dónde dejar a los jugadores al llegar.
@export var door_id: StringName = &"":
	set(value):
		door_id = value
		update_configuration_warnings()

## Ruta de la escena de la zona de destino.
@export_file("*.tscn") var target_zone: String = "":
	set(value):
		target_zone = value
		update_configuration_warnings()

## `door_id` de la puerta por la que se aparece en la zona de destino.
@export var target_door: StringName = &"":
	set(value):
		target_door = value
		update_configuration_warnings()

## Cuántos jugadores deben estar en la puerta para cruzar. 2 = se viaja junto.
@export_range(1, 2) var required_players: int = 2

@export var size: Vector2 = Vector2(96, 160):
	set(value):
		size = Vector2(maxf(value.x, 16.0), maxf(value.y, 16.0))
		_rebuild()

@export var editor_color: Color = Color(0.98, 0.72, 0.26, 0.28)

var _shape: CollisionShape2D
var _present: Array[int] = []


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	# Capas configuradas en la escena, no aquí (§13).
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group(&"zone_doors")


## Punto donde dejar a un jugador que llega por esta puerta.
func arrival_point() -> Vector2:
	return global_position


func _rebuild() -> void:
	if _shape == null:
		_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _shape == null:
		if not is_inside_tree():
			return
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		add_child(_shape)
		if Engine.is_editor_hint() and owner != null:
			_shape.owner = owner

	var rect := _shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_shape.shape = rect
	rect.size = size
	queue_redraw()
	update_configuration_warnings()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var local := Rect2(-size * 0.5, size)
	draw_rect(local, editor_color, true)
	draw_rect(local, Color(editor_color, 0.9), false, 3.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if door_id == &"":
		warnings.append("Asigna un `door_id`: la puerta de destino se refiere a esta por él.")
	if target_zone.is_empty():
		warnings.append("Sin `target_zone` la puerta no lleva a ninguna parte.")
	if target_door == &"":
		warnings.append("Asigna `target_door`: es la puerta por la que se aparece al llegar.")
	if collision_mask == 0:
		warnings.append("`collision_mask` a 0: nadie podrá activar la puerta. Marca la capa `player`.")
	return warnings


## Solo cuentan quienes viajan entre zonas. Se comprueba la pertenencia al
## grupo, no el tipo: un NPC acompañante podría contar sin tocar esta clase.
func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"zone_travellers"):
		return
	var id := body.get_instance_id()
	if _present.has(id):
		return
	_present.append(id)
	waiting_changed.emit(_present.size(), required_players)

	if _present.size() >= required_players:
		traversal_requested.emit(target_zone, target_door)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"zone_travellers"):
		return
	_present.erase(body.get_instance_id())
	waiting_changed.emit(_present.size(), required_players)
