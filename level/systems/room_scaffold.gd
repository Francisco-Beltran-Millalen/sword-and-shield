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
## Largo de una losa: 340 px, doce veces el ancho del cuerpo (28). Antes eran 40,
## o sea doce PÍXELES de paseo, y no se podía caminar sobre ellas.
##
## Que sean anchas solo es posible junto con `one_way_collision` (ver
## `_build_platforms`): macizas, una losa de 340 es un techo para la de abajo.
const PLATFORM_WIDTH: float = 340.0
## Desplazamiento entre una fila y la siguiente. Deja 210 px de SOLAPE, y ese
## solape es lo que hace subible la escalera: el jugador está debajo de la losa
## de arriba, salta, la atraviesa y aterriza encima. Sin solape habría que
## acertar un borde con una ventana de dos frames — medido, y descartado.
const PLATFORM_STAGGER: float = 130.0
const PLATFORM_THICKNESS: float = 24.0
## La escalera vive a la DERECHA de la columna del hueco de paso vertical, que
## queda libre de arriba abajo. Con la escalera centrada —como estaba— los
## peldaños ocupaban [-40,40] dentro de un hueco de [-70,70]: la escalera y el
## paso entre salas se disputaban la misma columna, y encima el centro de la
## sala es donde `arrival_point()` deja a los jugadores, que aparecían
## encaramados a 640 px de altura.
const PLATFORM_MARGIN: float = OPENING_WIDTH * 0.5

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
@export_range(24.0, 101.0, 1.0) var platform_rise: float = 80.0:
	set(value):
		platform_rise = value
		_rebuild()

## Paleta del andamio. Cuatro colores y no uno porque el graybox tiene que
## comunicar sus REGLAS, y la más importante de la sala —esto se atraviesa, esto
## no— era invisible: `one_way` viaja a la forma de colisión y no al dibujo, así
## que una losa que se cruza se pintaba igual que un suelo macizo.
##
## Van con setter y aquí, no repartidos desde `Zone._ready`: para entonces los
## `Polygon2D` ya están creados y el color llegaría tarde.
@export_group("Paleta")
## Donde se pisa: el más claro, porque es la superficie que se busca.
@export var floor_color: Color = Color(0.28, 0.32, 0.38, 1.0):
	set(value):
		floor_color = value
		_rebuild()
@export var wall_color: Color = Color(0.20, 0.23, 0.28, 1.0):
	set(value):
		wall_color = value
		_rebuild()
## El techo es el suelo de la sala de encima: se hunde para no competir con él.
@export var ceiling_color: Color = Color(0.14, 0.16, 0.20, 1.0):
	set(value):
		ceiling_color = value
		_rebuild()
## Las losas de un solo sentido. El color más separado de los otros tres: es la
## única pieza de la sala que se ATRAVIESA.
@export var platform_color: Color = Color(0.45, 0.49, 0.56, 1.0):
	set(value):
		platform_color = value
		_rebuild()
@export_group("")


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
	var tapa := Vector2(size.x, WALL_THICKNESS)
	var costado := Vector2(WALL_THICKNESS, size.y)
	_build_side(Side.TOP, Vector2(0.0, -half.y), tapa, true, ceiling_color)
	_build_side(Side.BOTTOM, Vector2(0.0, half.y), tapa, true, floor_color)
	_build_side(Side.LEFT, Vector2(-half.x, 0.0), costado, false, wall_color)
	_build_side(Side.RIGHT, Vector2(half.x, 0.0), costado, false, wall_color)
	_build_platforms()
	update_configuration_warnings()


func _build_side(side: int, center: Vector2, full_size: Vector2, horizontal: bool,
		color: Color) -> void:
	if openings & side == 0:
		_add_solid(center, full_size, false, color)
		return

	if horizontal:
		# Suelo y techo: dos tramos con el hueco centrado en X.
		var segment := maxf((size.x - OPENING_WIDTH) * 0.5, 0.0)
		if segment <= 0.0:
			return
		for direction: float in [-1.0, 1.0]:
			var offset := (OPENING_WIDTH * 0.5 + segment * 0.5) * direction
			_add_solid(center + Vector2(offset, 0.0), Vector2(segment, full_size.y), false, color)
		return

	# Pared lateral: el hueco se apoya en el suelo, así que solo queda el tramo
	# de arriba. Lo que quedaría por debajo cae dentro del propio suelo.
	var gap_top := floor_surface_y() - OPENING_HEIGHT
	var height := gap_top + size.y * 0.5
	if height <= 0.0:
		return
	_add_solid(Vector2(center.x, (gap_top - size.y * 0.5) * 0.5), Vector2(full_size.x, height),
			false, color)


## Escalera hasta el techo, a la derecha de la columna del hueco de paso, con
## losas anchas y de un solo sentido.
##
## Las tres piezas se sostienen entre sí y ninguna vale suelta:
##
## - **Anchas** (340 px) porque el encargo era poder caminar sobre ellas. Medido:
##   310 px de paseo sobre una losa, contra los 12 de antes.
## - **De un solo sentido** porque una losa ancha maciza es un techo para la de
##   abajo. Con `one_way` se sube atravesándola desde cualquier punto del solape.
##   Puesto SIN ensanchar, en cambio, hunde la escalera: quita el cabezazo del
##   que dependía la de antes —47 px de hueco contra un cuerpo de 44— y el
##   piloto pasaba de subir 856 px a 101. Por eso van en el mismo cambio.
## - **A un lado**, para que la columna del hueco quede libre de arriba abajo: es
##   por donde se sube y se baja entre salas, y por donde ya no aparecen los
##   jugadores encaramados.
##
## La ÚLTIMA fila es un descansillo que sí llega bajo la columna del hueco. Sin
## él no se sale por arriba: sobre una losa pegada al techo quedan 48 px contra
## un cuerpo de 44, así que saltar es darse en la cabeza a los 4 px y caerse los
## 1.200 de la sala. Medido: con descansillo se sale en 11 de 16 intentos; sin
## él, en 2 — y `verdant_5` y `cinder_5`, que solo abren arriba, quedaban
## sellados.
func _build_platforms() -> void:
	var steps := _step_count()
	if steps <= 1:
		return
	var rise := size.y / float(steps)
	var surface := floor_surface_y()
	var near_x := PLATFORM_MARGIN + PLATFORM_WIDTH * 0.5
	var far_x := near_x + PLATFORM_STAGGER

	for row in range(1, steps):
		var y := surface - rise * float(row)
		var x := near_x if row % 2 == 1 else far_x
		var ancho := PLATFORM_WIDTH
		if row == steps - 1:
			# El descansillo cruza la columna del hueco hacia la IZQUIERDA —hay
			# que poder ponerse DEBAJO de la abertura, no al lado— y por la
			# derecha llega justo a solapar con la fila de debajo, para subir a
			# él como a cualquier otra.
			var izquierda := -PLATFORM_MARGIN - PLATFORM_WIDTH * 0.35
			var derecha := far_x - PLATFORM_WIDTH * 0.5 + PLATFORM_MARGIN
			ancho = derecha - izquierda
			x = (izquierda + derecha) * 0.5
		# `_add_solid` centra el cuerpo; lo que importa es dónde queda la cara
		# que se pisa, que es la que separa una fila de la siguiente.
		_add_solid(Vector2(x, y + PLATFORM_THICKNESS * 0.5),
				Vector2(ancho, PLATFORM_THICKNESS), true, platform_color)


## Peldaños necesarios para subir del suelo al techo sin pasarse de
## `platform_rise` en ninguno. Se reparten uniformemente, así que ningún
## peldaño queda a una altura arbitraria por el resto de la división.
func _step_count() -> int:
	return maxi(ceili(size.y / maxf(platform_rise, 1.0)), 1)


## `one_way` se pasa solo en las losas: suelo, techo y paredes son macizos.
##
## No se toca `one_way_collision_margin`: con el valor por defecto (1.0) el
## jugador no se cuela ni cayendo a 3.710 px/s —medido—, y poniéndolo a 0 sí se
## cuela y acaba en el suelo.
func _add_solid(at: Vector2, extent: Vector2, one_way: bool, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1   ## capa `world`
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = extent
	shape.shape = rect
	shape.one_way_collision = one_way
	body.add_child(shape)

	var visual := Polygon2D.new()
	var half := extent * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	visual.color = color
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

	# Si la sala abre ARRIBA, hay que poder ponerse bajo la abertura y saltar. El
	# descansillo de la última fila es lo que lo permite; si por el reparto de
	# pasos no llega a cubrir la columna del hueco, la sala queda SELLADA y nada
	# lo dice. Medido: con `platform_rise = 100` la última fila cae a 130 px de
	# la columna y no se sale ni una vez de diez, en silencio. Un número del
	# inspector no puede cerrar una sala sin avisar (§13).
	if openings & Side.TOP != 0:
		if _step_count() > 1 and -PLATFORM_MARGIN - PLATFORM_WIDTH * 0.35 > -OPENING_WIDTH * 0.5:
			warnings.append(
				"La sala abre arriba y el descansillo no llega bajo el hueco: no se puede salir.")
	return warnings
