@tool
class_name RoomScaffold
extends Node2D

## Geometría **provisional** de una sala: suelo, techo, paredes y unas
## plataformas, generados a partir del tamaño y de qué lados están abiertos.
##
## Esto NO es contenido final. Existe para poder recorrer y probar la
## disposición de zonas y salas antes de que haya tileset y arte. Cuando lo
## haya, cada sala pinta su geometría con un `TileMapLayer` (con terrain sets
## para el autotile) y este nodo se retira — está anotado en el mapa de
## arquitectura para que no se quede aquí por inercia.
##
## Las aberturas se marcan con banderas en el inspector, así que conectar dos
## salas es marcar una casilla, no calcular huecos a mano.

## Lados de la sala. Los valores coinciden con las banderas de `openings`.
## Se pasa como `int` a `_build_side`: GDScript resuelve el enum propio de un
## script con `class_name` como `RoomScaffold.Side` en las firmas, y no casa
## consigo mismo al llamarlo desde dentro.
enum Side { TOP = 1, BOTTOM = 2, LEFT = 4, RIGHT = 8 }

const WALL_THICKNESS: float = 32.0
## Alto del hueco de paso en una pared abierta.
const OPENING_HEIGHT: float = 220.0
## Ancho del hueco de paso en un suelo o techo abierto.
const OPENING_WIDTH: float = 260.0

@export var size: Vector2 = Vector2(1280, 1280):
	set(value):
		size = Vector2(maxf(value.x, 256.0), maxf(value.y, 256.0))
		_rebuild()

## Lados por los que la sala conecta con sus vecinas.
@export_flags("Arriba", "Abajo", "Izquierda", "Derecha") var openings: int = 0:
	set(value):
		openings = value
		_rebuild()

## Filas de plataformas intermedias, para que una sala alta sea escalable.
@export_range(0, 6) var platform_rows: int = 2:
	set(value):
		platform_rows = value
		_rebuild()

@export var solid_color: Color = Color(0.17, 0.21, 0.26, 1.0)



func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		child.free()

	var half := size * 0.5
	# Paredes: cada lado se parte en dos tramos si tiene abertura.
	_build_side(Side.TOP, Vector2(0.0, -half.y), Vector2(size.x, WALL_THICKNESS), true)
	_build_side(Side.BOTTOM, Vector2(0.0, half.y), Vector2(size.x, WALL_THICKNESS), true)
	_build_side(Side.LEFT, Vector2(-half.x, 0.0), Vector2(WALL_THICKNESS, size.y), false)
	_build_side(Side.RIGHT, Vector2(half.x, 0.0), Vector2(WALL_THICKNESS, size.y), false)
	_build_platforms()


func _build_side(side: int, center: Vector2, full_size: Vector2, horizontal: bool) -> void:
	if openings & side == 0:
		_add_solid(center, full_size)
		return

	# Con abertura: dos tramos dejando el hueco en el centro.
	var gap := OPENING_WIDTH if horizontal else OPENING_HEIGHT
	var span := full_size.x if horizontal else full_size.y
	var segment := maxf((span - gap) * 0.5, 0.0)
	if segment <= 0.0:
		return

	for direction: float in [-1.0, 1.0]:
		var offset := (gap * 0.5 + segment * 0.5) * direction
		if horizontal:
			_add_solid(center + Vector2(offset, 0.0), Vector2(segment, full_size.y))
		else:
			# El hueco lateral se apoya en el suelo: es por donde se camina.
			var vertical_center := center.y + (size.y * 0.5 - segment * 0.5) * direction
			_add_solid(Vector2(center.x, vertical_center), Vector2(full_size.x, segment))


func _build_platforms() -> void:
	if platform_rows <= 0:
		return
	var usable := size.y - WALL_THICKNESS * 2.0
	var step := usable / float(platform_rows + 1)
	var width := size.x * 0.34

	for row in range(platform_rows):
		var y := size.y * 0.5 - step * float(row + 1)
		# Alternar el lado da una escalera en zigzag, escalable a saltos.
		var x := size.x * 0.22 * (1.0 if row % 2 == 0 else -1.0)
		_add_solid(Vector2(x, y), Vector2(width, 24.0))


func _add_solid(at: Vector2, extent: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1   ## capa `world`
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = extent
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	var half := extent * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	visual.color = solid_color
	body.add_child(visual)
