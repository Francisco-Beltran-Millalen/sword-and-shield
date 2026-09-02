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

## Marca de andamio: en partida se dibuja el marco de la puerta. Provisional,
## igual que `RoomScaffold`. Sin esto la salida es INVISIBLE mientras se juega:
## el HUD dice por qué una puerta no se abre, pero no dónde está.
@export var draw_placeholder: bool = true:
	set(value):
		draw_placeholder = value
		queue_redraw()

var _shape: CollisionShape2D
## Viajeros que han SALIDO del área desde la última llegada por esta puerta.
## Solo ellos pueden pedir viaje mientras `_received_arrival` esté puesto: ver
## `receive_arrival()`.
var _have_left: Array[int] = []
## ¿Se ha dejado aquí a alguien que acaba de cruzar? Lo empuja el `World`.
var _received_arrival: bool = false


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


## Cuántos viajeros hay ahora mismo dentro.
##
## Se le pregunta al motor en vez de llevar la cuenta a mano (§13). Medido: la
## lista ya refleja el evento en curso cuando se consulta desde `body_entered` o
## `body_exited`. Un conteo propio, además, se queda con fantasmas — un cuerpo
## liberado sin su `body_exited` dejaba la puerta muerta para siempre.
func travellers_inside() -> int:
	var total := 0
	for body in get_overlapping_bodies():
		if body.is_in_group(&"zone_travellers"):
			total += 1
	return total


## El `World` acaba de dejar aquí a quienes cruzaron: esta puerta los recibió, no
## los cruzó.
##
## Sin esto el viaje rebota sin fin. Los jugadores aparecen DENTRO del área de la
## puerta de destino —`arrival_point()` es su centro—, la puerta ve cumplidas sus
## condiciones en el paso de física siguiente y pide volver por donde se vino;
## medido, 20 cargas de zona en 4 segundos. La bandera `_changing_zone` del
## `World` no cubre esa ventana porque ya se ha liberado cuando la física
## resuelve los solapamientos.
##
## Que lo empuje el `World` y no lo adivine la puerta es deliberado (§5): solo el
## coordinador sabe que acaba de teletransportar cuerpos aquí. Deducirlo contando
## frames fallaría en red, donde el jugador remoto llega una latencia más tarde y
## su entrada parecería un cruce legítimo.
func receive_arrival() -> void:
	_received_arrival = true
	_have_left.clear()


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
		draw_rect(local, Color(editor_color, 0.9), false, 3.0)
		return
	if not draw_placeholder:
		return
	# Solo el marco: un relleno translúcido sobre el vano tapa a quien lo cruza,
	# y por aquí pasan los dos jugadores juntos.
	draw_rect(local, Color(editor_color, 0.85), false, 4.0)


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
	var inside := travellers_inside()
	# El conteo real siempre, aunque no se vaya a viajar: el HUD existe para
	# decir POR QUÉ una puerta no se abre, y mentirle aquí lo dejaría mudo justo
	# en ese caso.
	waiting_changed.emit(inside, required_players)
	if inside < required_players:
		return
	# Traído en brazos: apareció aquí porque el `World` lo dejó al llegar, no
	# porque haya cruzado. Para pedir viaje hay que haber salido antes, y basta
	# con que salga QUIEN ENTRA: un compañero parado dentro cuenta como presente
	# pero no encierra a nadie.
	if _received_arrival and not _have_left.has(body.get_instance_id()):
		return
	traversal_requested.emit(target_zone, target_door)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"zone_travellers"):
		return
	var id := body.get_instance_id()
	if _received_arrival and not _have_left.has(id):
		_have_left.append(id)
	waiting_changed.emit(travellers_inside(), required_players)
