@tool
class_name Zone
extends Node2D

## Raíz de una zona: la **unidad de carga** del mundo.
##
## Contiene sus salas (`RoomBounds`), su geometría y sus puertas. Se carga y se
## descarga entera; dentro de ella no hay carga ninguna, y los dos jugadores se
## mueven libremente sin importar en qué sala esté cada uno.
## Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`.
##
## Se valida en el editor (§13): si le falta un nodo obligatorio o una puerta
## está mal configurada, el aviso sale en el árbol de escenas, no en runtime.

@export var zone_id: StringName = &"":
	set(value):
		zone_id = value
		update_configuration_warnings()

## Sala donde aparecen los jugadores si entran a la zona sin puerta de origen
## (arranque de partida, carga de guardado).
@export var default_spawn_room: StringName = &""


func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()


## Todas las salas de esta zona.
func rooms() -> Array[RoomBounds]:
	var found: Array[RoomBounds] = []
	for node in find_children("*", "RoomBounds", true, false):
		var room := node as RoomBounds
		if room != null:
			found.append(room)
	return found


## La sala con ese `room_id`, o `null`.
func room(room_id: StringName) -> RoomBounds:
	for candidate in rooms():
		if candidate.room_id == room_id:
			return candidate
	return null


## Todas las puertas de salida de esta zona.
func doors() -> Array[ZoneDoor]:
	var found: Array[ZoneDoor] = []
	for node in find_children("*", "ZoneDoor", true, false):
		var door := node as ZoneDoor
		if door != null:
			found.append(door)
	return found


## La puerta con ese `door_id`, o `null`. La usa el `World` para colocar a los
## jugadores que llegan desde otra zona.
func door(door_id: StringName) -> ZoneDoor:
	for candidate in doors():
		if candidate.door_id == door_id:
			return candidate
	return null


## Dónde dejar a los jugadores al entrar. Si `from_door` nombra una puerta de
## esta zona, se aparece en ella; si no, sobre el SUELO de la sala por defecto.
func arrival_point(from_door: StringName = &"") -> Vector2:
	if from_door != &"":
		var entry := door(from_door)
		if entry != null:
			return entry.arrival_point()
	# `spawn_point()` y no `global_position`: el centro de la sala está 624 px por
	# encima del suelo, y aparecer ahí abría cada partida con seis metros de caída.
	var spawn_room := room(default_spawn_room)
	if spawn_room != null:
		return spawn_room.spawn_point()
	var all := rooms()
	if not all.is_empty():
		return all[0].spawn_point()
	return global_position


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if zone_id == &"":
		warnings.append("Asigna un `zone_id`.")

	var all := rooms()
	if all.is_empty():
		warnings.append("La zona no tiene ninguna `RoomBounds`.")

	var seen: Array[StringName] = []
	for candidate in all:
		if candidate.room_id == &"":
			continue
		if seen.has(candidate.room_id):
			warnings.append("`room_id` repetido: '%s'." % candidate.room_id)
		seen.append(candidate.room_id)

	if default_spawn_room != &"" and not seen.has(default_spawn_room):
		warnings.append("`default_spawn_room` ('%s') no existe en esta zona." % default_spawn_room)

	# Un cuerpo colocado con coordenadas de MUNDO bajo una sala que ya tiene su
	# propio `position` acaba en otra sala, o en ninguna: los dos offsets se
	# suman. Pasó con los tres enemigos de Verdant —uno de ellos caía al vacío
	# indefinidamente, medido a 7.163 px/s— y no lo veía nadie: la escena se
	# instancia igual y la suite seguía verde.
	#
	# El aviso vive AQUÍ y no solo en un test porque el error se comete en el
	# editor, arrastrando el nodo (§13: la validación de contenido es
	# `_get_configuration_warnings`; "avisos que solo se ven al jugar" es el
	# antipatrón que esa misma fila registra).
	for body in find_children("*", "CharacterBody2D", true, false):
		var home := _room_of(body)
		if home == null:
			continue
		var landed := &""
		for candidate in all:
			if candidate.world_rect().has_point(body.global_position):
				landed = candidate.room_id
				break
		if landed == &"":
			warnings.append(
				"'%s' cuelga de '%s' y no cae DENTRO DE NINGUNA sala: `position` es local, ¿está en coordenadas de mundo?"
				% [body.name, home.room_id])
		elif landed != home.room_id:
			warnings.append(
				"'%s' cuelga de '%s' pero cae en '%s': `position` es local, ¿está en coordenadas de mundo?"
				% [body.name, home.room_id, landed])

	return warnings


## La `RoomBounds` de la rama de la que cuelga un nodo, o `null` si no cuelga de
## ninguna sala. Se sube por el árbol en vez de exigir una profundidad concreta:
## un enemigo puede colgar de la sala o de un contenedor dentro de ella.
func _room_of(node: Node) -> RoomBounds:
	var walker := node.get_parent()
	while walker != null and walker != self:
		for child in walker.get_children():
			var bounds := child as RoomBounds
			if bounds != null:
				return bounds
		walker = walker.get_parent()
	return null
