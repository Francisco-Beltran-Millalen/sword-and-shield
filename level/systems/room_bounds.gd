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

## Entró un ocupante en esta sala (jugador, enemigo, NPC…).
@warning_ignore("unused_signal")
signal occupant_entered(room_id: StringName, occupant: Node)

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

## Marca de andamio: en partida se dibuja el borde de la sala y su `room_id`.
## Provisional, igual que `RoomScaffold`, y por la misma razón: las diez salas
## miden lo mismo y llevan la misma escalera, así que nada en pantalla decía en
## cuál estabas. Se apaga desde el inspector para mirar el nivel limpio.
@export var draw_placeholder: bool = true:
	set(value):
		draw_placeholder = value
		queue_redraw()

## Tamaño y margen de la marca de sala, en píxeles de mundo.
const ETIQUETA: int = 40
const MARGEN: float = 28.0

var _shape: CollisionShape2D


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	monitoring = true
	# Las capas se configuran en la escena, desde el inspector, donde tienen
	# nombre (§13). Escribirlas aquí pisaba lo que el diseñador eligiera.
	body_entered.connect(_on_body_entered)


## Rectángulo de la sala en coordenadas de mundo. Es lo que la cámara usa como
## límite.
func world_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


## Dónde dejar a quien entra en esta sala sin puerta de origen.
##
## Se apoya en el SUELO, no en el centro geométrico: con salas de 1280 px, el
## centro está 624 px por encima del piso y la partida abría con seis metros de
## caída — medido grabando, a los 0,5 s el jugador todavía no había aterrizado.
##
## Quién sabe dónde está el suelo se pregunta por el MÉTODO y no por el tipo
## (§7), como ya hace `_on_body_entered` con `enter_room`: hoy lo responde el
## andamio, mañana un `TileMapLayer`, y esta clase no tiene por qué enterarse.
## Si nadie lo sabe, el centro sigue siendo la respuesta.
func spawn_point() -> Vector2:
	var parent := get_parent()
	if parent == null:
		return global_position
	for sibling in parent.get_children():
		if sibling == self or not sibling.has_method(&"floor_surface_y"):
			continue
		var ground := sibling as Node2D
		if ground == null:
			continue
		var surface: float = ground.call(&"floor_surface_y")
		return Vector2(global_position.x, ground.global_position.y + surface)
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
	var local := Rect2(-size * 0.5, size)
	if Engine.is_editor_hint():
		draw_rect(local, editor_color, true)
		draw_rect(local, Color(editor_color, 0.85), false, 3.0)
		return
	if not draw_placeholder:
		return

	# En partida, BORDE y nombre; nunca el relleno. Las salas teselan la zona sin
	# solaparse —lo fija `test_zones.gd`—, así que un lavado uniforme es idéntico
	# en todas partes: no dice dónde estás, solo tiñe. Y con el `z_index` de la
	# capa de marcas quedaría por encima de toda la geometría de su propia sala.
	draw_rect(local, Color(editor_color, 0.55), false, 4.0)
	if room_id == &"":
		return
	# La fuente la sirve el motor: no hay `.ttf` en el proyecto y una marca de
	# andamio no justifica traerlo (§13).
	var font := ThemeDB.fallback_font
	if font == null:
		return
	# En las CUATRO esquinas, no en una. La cámara enseña 1200x675 px de una sala
	# de 1280x1280: con una sola etiqueta arriba a la izquierda, quien está en el
	# suelo —que es donde se empieza— no la ve nunca. Medido grabando.
	var nombre := String(room_id)
	var ancho := font.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ETIQUETA).x
	var tinta := Color(editor_color, 0.55)
	for esquina: Vector2 in [
		local.position + Vector2(MARGEN, MARGEN + ETIQUETA),
		local.position + Vector2(local.size.x - MARGEN - ancho, MARGEN + ETIQUETA),
		local.position + Vector2(MARGEN, local.size.y - MARGEN),
		local.position + Vector2(local.size.x - MARGEN - ancho, local.size.y - MARGEN),
	]:
		draw_string(font, esquina, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ETIQUETA, tinta)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if room_id == &"":
		warnings.append("Asigna un `room_id`: las puertas y el guardado se refieren a la sala por él.")
	if size.x < 320.0 or size.y < 240.0:
		warnings.append("La sala es más pequeña que una pantalla; la cámara no tendrá recorrido.")
	if collision_mask == 0:
		warnings.append("`collision_mask` a 0: la sala no detectará a nadie. Marca las capas `player` / `enemy`.")
	return warnings


## Cualquier entidad puede habitar una sala. Solo se le avisa si le interesa
## saberlo: se comprueba el MÉTODO, no el tipo, así que un enemigo o un NPC
## participan sin que esta clase los conozca (§7).
func _on_body_entered(body: Node2D) -> void:
	# El aviso es para cualquier ocupante; reencuadrar la cámara, solo para
	# quien tenga una. Emitir después del `return` dejaba la señal muerta para
	# enemigos y NPC, que es justo lo que su nombre promete cubrir.
	if body.has_method("enter_room"):
		body.enter_room(room_id, world_rect())
		# Al bus solo el ocupante LOCAL, y solo por la sala: quien mira esto —hoy
		# el overlay de depuración, mañana el mapa— cuelga del `World` y no puede
		# conocer a una sala que vive dentro de la zona, que es la primera de las
		# tres condiciones de `GameEvents` (§1). Los remotos no cuentan: cada peer
		# encuadra al suyo, así que "en qué sala estoy" es una pregunta local.
		if body.is_multiplayer_authority():
			GameEvents.room_entered.emit(room_id)
	occupant_entered.emit(room_id, body)
