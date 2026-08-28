@tool
class_name RoomBounds
extends Area2D

## Una sala: unidad de **diseño y de cámara**, no de carga.
##
## No se carga ni se descarga — vive dentro de su zona desde que la zona entra
## en el árbol. Lo único que hace al entrar un jugador es reencuadrar su cámara.
## Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`.
##
## Se dibuja sola en el editor a partir de `size` (`@tool` +
## `_get_configuration_warnings`), así que colocar salas es arrastrar y
## redimensionar, no calcular rectángulos a mano (§13).

## Un jugador local entró en esta sala.
@warning_ignore("unused_signal")
signal player_entered(room_id: StringName, player: Node)

## Identificador de la sala, único dentro de su zona. Lo usan las puertas y el
## sistema de guardado.
@export var room_id: StringName = &"":
	set(value):
		room_id = value
		update_configuration_warnings()

## Tamaño de la sala en píxeles. La forma de colisión se regenera a partir de él.
@export var size: Vector2 = Vector2(1280, 1280):
	set(value):
		size = Vector2(maxf(value.x, 64.0), maxf(value.y, 64.0))
		_rebuild()

## Color del rectángulo guía en el editor. No se dibuja en la partida.
@export var editor_color: Color = Color(0.24, 0.78, 0.92, 0.10)

var _shape: CollisionShape2D


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	monitoring = true
	# Solo detecta cuerpos en la capa `player`.
	collision_layer = 0
	collision_mask = 1 << 1
	body_entered.connect(_on_body_entered)


## Rectángulo de la sala en coordenadas de mundo. Es lo que la cámara usa como
## límite.
func world_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


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
	draw_rect(local, Color(editor_color, 0.85), false, 3.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if room_id == &"":
		warnings.append("Asigna un `room_id`: las puertas y el guardado se refieren a la sala por él.")
	if size.x < 320.0 or size.y < 240.0:
		warnings.append("La sala es más pequeña que una pantalla; la cámara no tendrá recorrido.")
	return warnings


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or not player.is_local_player():
		return
	# Llamada a la API pública del jugador, no escritura sobre su cámara (§2).
	player.enter_room(room_id, world_rect())
	player_entered.emit(room_id, player)
