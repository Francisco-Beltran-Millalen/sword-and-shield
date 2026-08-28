extends GutTest

## Cruzar de zona, conducido de verdad.
##
## Este archivo existe por un fallo que la suite daba en verde: al llegar a una
## zona los jugadores aparecen DENTRO del área de la puerta de destino —
## `arrival_point()` es su centro—, la puerta veía cumplidas sus condiciones y
## pedía volver por donde se había venido. Medido antes del arreglo: veinte
## cargas de zona en cuatro segundos, sin parar. Ningún test cruzaba una puerta.

const WorldScene := preload("res://systems/world/world.tscn")

var world: Node2D
var zonas: Array[String] = []


func before_each() -> void:
	world = WorldScene.instantiate() as Node2D
	add_child_autofree(world)
	zonas = []
	GameEvents.zone_entered.connect(_anotar_zona)
	await wait_physics_frames(2)
	# Sin sesión de red el World hace aparecer un solo jugador (peers = [1]), y
	# la puerta exige dos. Se monta el segundo por el mismo spawner que usa la
	# partida, para no probar contra una escena que el juego nunca tiene.
	if _viajeros().size() < 2:
		world.spawner.spawn({"peer": 2, "index": 1})
		await wait_physics_frames(2)


func after_each() -> void:
	if GameEvents.zone_entered.is_connected(_anotar_zona):
		GameEvents.zone_entered.disconnect(_anotar_zona)


func _anotar_zona(id: StringName) -> void:
	zonas.append(str(id))


func _puerta() -> ZoneDoor:
	return world.current_zone.doors()[0]


func _viajeros() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"zone_travellers")


## Lleva a todos los viajeros encima de la puerta, como haría el juego.
func _llevar_a(punto: Vector2) -> void:
	for viajero in _viajeros():
		viajero.place_at(punto)


func test_hay_dos_viajeros_para_exigir_la_puerta() -> void:
	# Si no hubiera dos, la puerta nunca se dispararía y el resto del archivo
	# estaría midiendo una escena en la que no puede pasar nada.
	assert_gte(_viajeros().size(), 2, "la puerta exige dos jugadores")


func test_cruzar_una_puerta_carga_una_zona_y_solo_una() -> void:
	var destino := _puerta().target_zone
	_llevar_a(_puerta().global_position)
	await wait_physics_frames(240)

	assert_eq(zonas.size(), 1,
			"una zona nueva y ninguna más; si son varias, el viaje está rebotando: %s"
			% str(zonas))
	assert_true(destino.ends_with("%s.tscn" % zonas[0]),
			"se llegó a la zona que la puerta nombraba")


func test_la_puerta_de_llegada_no_devuelve_a_nadie() -> void:
	_llevar_a(_puerta().global_position)
	await wait_physics_frames(240)

	var llegada := world.current_zone.doors()[0] as ZoneDoor
	assert_gt(llegada.travellers_inside(), 0,
			"se aparece dentro del área de la puerta de llegada: ese es el caso que importa")
	assert_eq(zonas.size(), 1, "y aun así no se viaja de vuelta")


func test_quien_llega_tarde_tampoco_dispara_el_viaje() -> void:
	# El caso de red: el jugador remoto aparece una latencia más tarde, así que
	# su `body_entered` llega mucho después de la carga. Deducir el estado de la
	# puerta contando frames no lo cubriría.
	var puerta := _puerta()
	var viajeros := _viajeros()
	viajeros[0].place_at(puerta.global_position)
	await wait_physics_frames(2)
	viajeros[1].place_at(puerta.global_position)
	await wait_physics_frames(240)

	assert_eq(zonas.size(), 1, "llegar escalonados no debe rebotar: %s" % str(zonas))


func test_salir_y_volver_a_entrar_si_cruza() -> void:
	# El arreglo no puede dejar la puerta muerta: viajar de vuelta a propósito
	# tiene que seguir funcionando.
	_llevar_a(_puerta().global_position)
	await wait_physics_frames(120)
	assert_eq(zonas.size(), 1, "se llegó a la zona nueva")

	var llegada := world.current_zone.doors()[0] as ZoneDoor
	# Cada peer coloca al suyo al cambiar de zona, así que el segundo jugador de
	# este proceso lo reúne el test.
	_llevar_a(llegada.global_position)
	await wait_physics_frames(10)
	var lejos := llegada.global_position + Vector2(0.0, -4000.0)
	_llevar_a(lejos)
	await wait_physics_frames(10)
	assert_eq(llegada.travellers_inside(), 0, "todos fuera del área")

	_llevar_a(llegada.global_position)
	await wait_physics_frames(120)
	assert_eq(zonas.size(), 2,
			"tras salir y volver a entrar sí se viaja: %s" % str(zonas))


func test_un_companero_parado_dentro_no_encierra_a_nadie() -> void:
	# Si la puerta exigiera vaciarse del todo para rearmarse, uno quieto dentro
	# dejaría el viaje imposible para siempre y sin explicación.
	_llevar_a(_puerta().global_position)
	await wait_physics_frames(120)

	var llegada := world.current_zone.doors()[0] as ZoneDoor
	# El segundo jugador lo coloca SU peer, que en una partida real es el otro
	# proceso: aquí ese papel lo hace el test.
	_llevar_a(llegada.global_position)
	await wait_physics_frames(10)

	var viajeros := _viajeros()
	# Uno se queda dentro; el otro sale y vuelve.
	viajeros[0].place_at(llegada.global_position + Vector2(0.0, -4000.0))
	await wait_physics_frames(10)
	viajeros[0].place_at(llegada.global_position)
	await wait_physics_frames(120)

	assert_eq(zonas.size(), 2,
			"con el compañero quieto dentro, quien sale y entra sigue pudiendo viajar")
