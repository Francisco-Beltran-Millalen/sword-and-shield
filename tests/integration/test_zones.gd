extends GutTest

## Zonas y salas. Lo que se prueba aquí es la decisión del ADR-001: la zona es
## la unidad de carga y la sala solo reencuadra la cámara.

const VerdantScene := preload("res://level/zones/zone_verdant.tscn")
const CinderScene := preload("res://level/zones/zone_cinder.tscn")
const PlayerScene := preload("res://characters/player/player.tscn")

var zone: Zone


func before_each() -> void:
	zone = VerdantScene.instantiate() as Zone
	add_child_autofree(zone)


func test_la_zona_verdant_tiene_cinco_salas() -> void:
	assert_eq(zone.rooms().size(), 5)


func test_la_zona_cinder_tiene_cinco_salas() -> void:
	var cinder := CinderScene.instantiate() as Zone
	add_child_autofree(cinder)
	assert_eq(cinder.rooms().size(), 5)


func test_las_salas_se_encuentran_por_id() -> void:
	var room := zone.room(&"verdant_2")
	assert_not_null(room, "verdant_2 debe existir")
	assert_eq(room.room_id, &"verdant_2")


func test_una_sala_inexistente_devuelve_null() -> void:
	assert_null(zone.room(&"no_existe"))


func test_los_ids_de_sala_no_se_repiten() -> void:
	var seen: Array[StringName] = []
	for room in zone.rooms():
		assert_false(seen.has(room.room_id), "id repetido: %s" % room.room_id)
		seen.append(room.room_id)


func test_las_salas_son_cuadradas() -> void:
	for room in zone.rooms():
		assert_almost_eq(room.size.x, room.size.y, 0.01,
				"la sala %s debe ser cuadrada" % room.room_id)


func test_el_rectangulo_de_sala_esta_centrado_en_su_posicion() -> void:
	var room := zone.room(&"verdant_1")
	var rect := room.world_rect()
	assert_almost_eq(rect.get_center().x, room.global_position.x, 0.01)
	assert_almost_eq(rect.get_center().y, room.global_position.y, 0.01)
	assert_almost_eq(rect.size.x, room.size.x, 0.01)


func test_las_salas_no_se_solapan() -> void:
	var rooms := zone.rooms()
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var a := rooms[i].world_rect()
			var b := rooms[j].world_rect()
			# Se encogen 1px para que compartir borde no cuente como solape.
			assert_false(a.grow(-1.0).intersects(b.grow(-1.0)),
					"%s y %s se solapan" % [rooms[i].room_id, rooms[j].room_id])


func test_la_puerta_apunta_a_la_otra_zona() -> void:
	var door := zone.door(&"verdant_east")
	assert_not_null(door, "verdant_east debe existir")
	assert_eq(door.target_zone, "res://level/zones/zone_cinder.tscn")
	assert_eq(door.target_door, &"cinder_west")


func test_las_puertas_de_ambas_zonas_se_emparejan() -> void:
	var cinder := CinderScene.instantiate() as Zone
	add_child_autofree(cinder)

	var salida := zone.door(&"verdant_east")
	var llegada := cinder.door(salida.target_door)
	assert_not_null(llegada, "la puerta de destino debe existir en la zona de llegada")
	assert_eq(llegada.target_door, salida.door_id,
			"y debe devolver a la puerta de origen")


func test_cruzar_de_zona_exige_a_los_dos_jugadores() -> void:
	var door := zone.door(&"verdant_east")
	assert_eq(door.required_players, 2,
			"el viaje entre zonas es conjunto: elimina el caso de jugadores en zonas distintas")


func test_el_punto_de_llegada_usa_la_puerta_nombrada() -> void:
	var door := zone.door(&"verdant_east")
	var arrival := zone.arrival_point(&"verdant_east")
	assert_almost_eq(arrival.x, door.global_position.x, 0.01)
	assert_almost_eq(arrival.y, door.global_position.y, 0.01)


func test_sin_puerta_se_llega_a_la_sala_por_defecto() -> void:
	var arrival := zone.arrival_point(&"")
	var spawn_room := zone.room(zone.default_spawn_room)
	assert_not_null(spawn_room)
	assert_almost_eq(arrival.x, spawn_room.global_position.x, 0.01)


func test_la_zona_no_tiene_avisos_de_configuracion() -> void:
	assert_eq(zone._get_configuration_warnings().size(), 0,
			"una zona bien montada no debe avisar en el editor")


func test_entrar_en_una_sala_reencuadra_la_camara_del_jugador() -> void:
	var player := PlayerScene.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame

	var room := zone.room(&"verdant_2")
	player.enter_room(room.room_id, room.world_rect())

	assert_eq(player.current_room, &"verdant_2")
	assert_eq(player.camera.limit_left, int(room.world_rect().position.x),
			"la cámara queda encerrada en la sala")
	assert_eq(player.camera.limit_right, int(room.world_rect().end.x))


## --- Geometría del scaffold ---
##
## Estos tests existen por un fallo real: `room_scaffold.gd` no compilaba y la
## suite seguía en verde, porque un error de parseo deja al nodo sin script sin
## romper la instanciación de la zona. Las salas quedaban sin suelo y nadie se
## enteraba. Contar la geometría lo caza.

func test_las_salas_generan_geometria_solida() -> void:
	var solidos := zone.find_children("*", "StaticBody2D", true, false)
	assert_gt(solidos.size(), 20,
			"5 salas con paredes y plataformas deben producir geometría; " +
			"cero significa que el scaffold no compiló")


func test_cada_sala_tiene_su_propia_geometria() -> void:
	for node in zone.find_children("*", "RoomScaffold", true, false):
		var scaffold := node as RoomScaffold
		assert_not_null(scaffold, "el nodo debe conservar su script")
		var solidos := scaffold.find_children("*", "StaticBody2D", false, false)
		assert_gt(solidos.size(), 0, "una sala sin geometría no tiene suelo")


func test_un_lado_abierto_deja_menos_pared_que_uno_cerrado() -> void:
	# verdant_2 abre a los cuatro lados; verdant_5 solo por arriba. Contar
	# cuerpos no sirve —un lado vertical abierto deja un solo tramo, igual que
	# uno cerrado—, pero abrir siempre quita material: se mide el área.
	var cruce := _scaffold_de(&"verdant_2")
	var fondo := _scaffold_de(&"verdant_5")
	assert_not_null(cruce)
	assert_not_null(fondo)

	assert_lt(_area_de_pared(cruce), _area_de_pared(fondo),
			"cada abertura recorta pared: cuatro dejan menos que una")


func _area_de_pared(scaffold: RoomScaffold) -> float:
	var total := 0.0
	for nodo in scaffold.find_children("*", "StaticBody2D", false, false):
		var forma := nodo.get_child(0) as CollisionShape2D
		var medida: Vector2 = (forma.shape as RectangleShape2D).size
		# Por GROSOR, no por ancho. Filtrando por ancho, una losa de 340
		# descartaba también las PAREDES (32 px de ancho) y el test seguía
		# pasando por casualidad mientras ya no medía lo que dice medir.
		if medida.y <= RoomScaffold.PLATFORM_THICKNESS:
			continue   ## losa, no pared
		total += medida.x * medida.y
	return total


func _scaffold_de(room_id: StringName) -> RoomScaffold:
	for node in zone.find_children("*", "RoomScaffold", true, false):
		var parent := node.get_parent()
		if parent == null:
			continue
		var bounds := parent.get_node_or_null("Bounds") as RoomBounds
		if bounds != null and bounds.room_id == room_id:
			return node as RoomScaffold
	return null


## --- Que lo colocado en una sala esté DENTRO de esa sala ---

## `position` es LOCAL, y cada nodo `Room*` ya lleva el suyo: quien escribe ahí
## coordenadas de mundo suma los dos offsets. Los tres enemigos de Verdant
## estaban así — dos caían en `verdant_3` en vez de `verdant_2`, y el tercero no
## caía en ninguna sala: medido, a los 300 fotogramas iba por y=18986 bajando a
## 7.163 px/s, para siempre.
##
## Nada lo veía. La escena se instancia igual, el enemigo existe, y la suite
## seguía verde: no había un solo test que preguntara DÓNDE acaban las cosas.
##
## Se afirma sobre la posición AUTORADA, sin simular: los enemigos patrullan
## (`patrol_radius`), así que uno legítimamente pegado al borde de su sala puede
## salirse tras unos frames y haría fallar al test por moverse, no por estar mal.
func test_lo_que_cuelga_de_una_sala_cae_dentro_de_esa_sala() -> void:
	for ruta in [
		"res://level/zones/zone_verdant.tscn",
		"res://level/zones/zone_cinder.tscn",
	]:
		var escena: Node = load(ruta).instantiate()
		add_child_autofree(escena)

		var salas: Array = escena.find_children("*", "RoomBounds", true, false)
		assert_gt(salas.size(), 0, "%s tiene salas" % ruta.get_file())

		for cuerpo in escena.find_children("*", "CharacterBody2D", true, false):
			var punto: Vector2 = cuerpo.global_position
			var donde := &""
			for sala in salas:
				if (sala.world_rect() as Rect2).has_point(punto):
					donde = sala.room_id
					break
			assert_ne(donde, &"",
					"%s: '%s' en %s no cae dentro de ninguna sala"
					% [ruta.get_file(), cuerpo.name, punto])
