@tool
class_name RoomScaffold
extends Node2D

## Geometría **provisional** de una sala: suelo, techo, paredes y una escalera,
## generados a partir del tamaño y de qué lados están abiertos.
##
## Esto NO es contenido final. Existe para poder recorrer y probar la
## disposición de zonas y salas antes de que haya tileset y arte. Cuando lo
## haya, cada sala pinta su geometría con un `TileMapLayer` (con terrain sets
## para el autotile) y este nodo se retira — está anotado en el mapa de
## arquitectura para que no se quede aquí por inercia.
##
## Las aberturas se marcan con banderas en el inspector, así que conectar dos
## salas es marcar una casilla, no calcular huecos a mano.
##
## Toda medida de paso sale del alcance real del jugador, medido en
## `tests/integration/test_room_traversal.gd`. Un andamio que genera un hueco
## incruzable no rompe nada ni avisa: la sala queda incomunicada y la suite
## sigue en verde. Ya pasó — el hueco lateral se dibujaba a media altura de la
## pared y la primera sala era una trampa sin salida.

## Lados de la sala. Los valores coinciden con las banderas de `openings`.
## Se pasa como `int` a `_build_side`: GDScript resuelve el enum propio de un
## script con `class_name` como `RoomScaffold.Side` en las firmas, y no casa
## consigo mismo al llamarlo desde dentro.
enum Side { TOP = 1, BOTTOM = 2, LEFT = 4, RIGHT = 8 }

const WALL_THICKNESS: float = 32.0
## Alto del hueco de paso en una pared abierta. El hueco se apoya en el suelo:
## a la sala vecina se entra caminando, no saltando a media pared.
const OPENING_HEIGHT: float = 220.0
## Ancho del hueco de paso en un suelo o techo abierto. Por debajo del alcance
## horizontal del salto (163 px con los stats base) para que un agujero en el
## suelo se cruce de un salto en vez de partir la sala en dos.
const OPENING_WIDTH: float = 140.0
## Cuánto se desplaza cada peldaño respecto al eje de la escalera. El salto de
## uno al siguiente exige cruzar como mucho el doble de esto, y el jugador solo
## avanza ~40 px mientras gana `platform_rise` de altura.
const PLATFORM_STAGGER: float = 20.0
## Justo el doble del desplazamiento: así dos peldaños consecutivos se tocan de
## canto sin solaparse, y NINGÚN punto de un peldaño tiene el siguiente encima.
## Con solape, el trozo utilizable se queda sin altura para saltar —72 px de
## subida contra un cuerpo de 44— y la escalera se atasca aunque cada peldaño
## esté al alcance. Medido conduciendo un jugador, no deducido.
const PLATFORM_WIDTH: float = PLATFORM_STAGGER * 2.0
const PLATFORM_THICKNESS: float = 24.0

@export var size: Vector2 = Vector2(1280, 1280):
	set(value):
		size = Vector2(maxf(value.x, 256.0), maxf(value.y, 256.0))
		_rebuild()

## Lados por los que la sala conecta con sus vecinas.
@export_flags("Arriba", "Abajo", "Izquierda", "Derecha") var openings: int = 0:
	set(value):
		openings = value
		_rebuild()

## Cuánto sube cada peldaño de la escalera. El tope es la altura de salto del
## jugador con los stats base (101 px medidos); el valor por defecto deja
## margen. La escalera llega siempre hasta el techo, así que el número de
## peldaños se deduce de aquí y del alto de la sala — no se configura sala por
## sala, que es como se acababa con aberturas inalcanzables.
@export_range(24.0, 101.0, 1.0) var platform_rise: float = 72.0:
	set(value):
		platform_rise = value
		_rebuild()

@export var solid_color: Color = Color(0.17, 0.21, 0.26, 1.0)


func _ready() -> void:
	_rebuild()


## Cara por la que se pisa el suelo de la sala, en coordenadas locales.
func floor_surface_y() -> float:
	return size.y * 0.5 - WALL_THICKNESS * 0.5


## Cara superior del techo: es el suelo de la sala de encima, y por tanto la
## altura a la que hay que llegar para cruzar una abertura superior.
func ceiling_surface_y() -> float:
	return -size.y * 0.5 - WALL_THICKNESS * 0.5


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		child.free()

	var half := size * 0.5
	# Paredes: cada lado se parte si tiene abertura.
	_build_side(Side.TOP, Vector2(0.0, -half.y), Vector2(size.x, WALL_THICKNESS), true)
	_build_side(Side.BOTTOM, Vector2(0.0, half.y), Vector2(size.x, WALL_THICKNESS), true)
	_build_side(Side.LEFT, Vector2(-half.x, 0.0), Vector2(WALL_THICKNESS, size.y), false)
	_build_side(Side.RIGHT, Vector2(half.x, 0.0), Vector2(WALL_THICKNESS, size.y), false)
	_build_platforms()
	update_configuration_warnings()


func _build_side(side: int, center: Vector2, full_size: Vector2, horizontal: bool) -> void:
	if openings & side == 0:
		_add_solid(center, full_size)
		return

	if horizontal:
		# Suelo y techo: dos tramos con el hueco centrado en X.
		var segment := maxf((size.x - OPENING_WIDTH) * 0.5, 0.0)
		if segment <= 0.0:
			return
		for direction: float in [-1.0, 1.0]:
			var offset := (OPENING_WIDTH * 0.5 + segment * 0.5) * direction
			_add_solid(center + Vector2(offset, 0.0), Vector2(segment, full_size.y))
		return

	# Pared lateral: el hueco se apoya en el suelo, así que solo queda el tramo
	# de arriba. Lo que quedaría por debajo cae dentro del propio suelo.
	var gap_top := floor_surface_y() - OPENING_HEIGHT
	var height := gap_top + size.y * 0.5
	if height <= 0.0:
		return
	_add_solid(Vector2(center.x, (gap_top - size.y * 0.5) * 0.5), Vector2(full_size.x, height))


## Escalera hasta el techo, escalonada a un lado y a otro del eje. Va centrada
## y estrecha para que quepa entera bajo la abertura superior: un peldaño ancho
## pegado al techo macizo deja al jugador sin sitio para ponerse de pie.
func _build_platforms() -> void:
	var steps := _step_count()
	if steps <= 1:
		return
	var rise := size.y / float(steps)
	var surface := floor_surface_y()

	for row in range(1, steps):
		var y := surface - rise * float(row)
		var x := PLATFORM_STAGGER if row % 2 == 1 else -PLATFORM_STAGGER
		# `_add_solid` centra el cuerpo; lo que importa es dónde queda la cara
		# que se pisa, que es la que separa un peldaño del siguiente.
		_add_solid(Vector2(x, y + PLATFORM_THICKNESS * 0.5),
				Vector2(PLATFORM_WIDTH, PLATFORM_THICKNESS))


## Peldaños necesarios para subir del suelo al techo sin pasarse de
## `platform_rise` en ninguno. Se reparten uniformemente, así que ningún
## peldaño queda a una altura arbitraria por el resto de la división.
func _step_count() -> int:
	return maxi(ceili(size.y / maxf(platform_rise, 1.0)), 1)


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


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if size.y < OPENING_HEIGHT + WALL_THICKNESS * 2.0:
		warnings.append(
			"La sala mide %d px de alto y el hueco de paso lateral pide %d: no cabe."
			% [int(size.y), int(OPENING_HEIGHT + WALL_THICKNESS * 2.0)])
	if size.x < OPENING_WIDTH + WALL_THICKNESS * 2.0:
		warnings.append(
			"La sala mide %d px de ancho y el hueco de paso vertical pide %d: no cabe."
			% [int(size.x), int(OPENING_WIDTH + WALL_THICKNESS * 2.0)])
	var rise := size.y / float(_step_count())
	if rise > platform_rise + 0.5:
		warnings.append(
			"Los peldaños suben %d px y el tope es %d: la sala no se puede escalar."
			% [int(rise), int(platform_rise)])
	return warnings
