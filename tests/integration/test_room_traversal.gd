extends GutTest

## ¿Se puede recorrer lo que el andamio genera?
##
## Existe por el fallo más caro de la revisión: el juego arrancaba, la suite
## daba 119/119 y el jugador caía en la primera sala sin poder salir. El hueco
## de paso estaba dibujado a 514 px del suelo y las plataformas a 401, contra
## un salto de 101. Nada falla cuando una sala es una trampa — hay que medirlo.
##
## Por eso aquí no se comprueban números escritos a mano: se **mide** lo que el
## jugador puede hacer conduciendo uno de verdad, y se contrasta con lo que el
## andamio dibuja. Si alguien toca `JUMP_VELOCITY` o la gravedad, este test
## sigue siendo válido y avisa si la geometría deja de ser alcanzable.

const Harness := preload("res://tests/integration/_harness.gd")
const ScaffoldScript := preload("res://level/systems/room_scaffold.gd")
const VerdantScene := preload("res://level/zones/zone_verdant.tscn")
const CinderScene := preload("res://level/zones/zone_cinder.tscn")

var h: IntegrationHarness


func before_each() -> void:
	h = Harness.new()
	add_child(h)


func after_each() -> void:
	h.teardown()


## --- Lo que el jugador puede hacer, medido ---

func test_la_subida_entre_apoyos_cabe_en_un_salto() -> void:
	h.setup()
	var salto := await _medir_altura_de_salto()
	gut.p("altura de salto medida: %.1f px" % salto)

	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.TOP)
	var subida := _subida_maxima(scaffold)
	gut.p("subida máxima entre apoyos: %.1f px" % subida)

	assert_lt(subida, salto,
			"un peldaño más alto que el salto deja la sala incomunicada")


func test_el_hueco_del_suelo_se_cruza_de_un_salto() -> void:
	h.setup()
	var alcance := await _medir_alcance_horizontal()
	gut.p("alcance horizontal de salto medido: %.1f px" % alcance)

	assert_lt(RoomScaffold.OPENING_WIDTH, alcance,
			"un agujero más ancho que el salto parte la sala en dos: " +
			"quien camina hacia la salida se cae dentro y no vuelve")


## --- Lo que el andamio dibuja ---

func test_el_hueco_lateral_se_pisa_desde_el_suelo() -> void:
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.RIGHT)
	var pared := _tramo_de_pared_derecha(scaffold)
	assert_not_null(pared, "un lado abierto deja tramo de pared por encima del hueco")

	var borde_inferior: float = pared.position.y + _extent(pared).y * 0.5
	var altura_del_hueco := scaffold.floor_surface_y() - borde_inferior
	assert_almost_eq(altura_del_hueco, RoomScaffold.OPENING_HEIGHT, 1.0,
			"el hueco se apoya en el suelo: a la sala vecina se entra caminando")


func test_el_ultimo_peldano_queda_bajo_la_abertura_superior() -> void:
	# Un peldaño ancho pegado al techo macizo deja al jugador sin sitio para
	# ponerse de pie: cabe tumbado y no puede saltar.
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.TOP)
	var mas_alto: StaticBody2D = null
	for cuerpo in _peldanos(scaffold):
		if mas_alto == null or cuerpo.position.y < mas_alto.position.y:
			mas_alto = cuerpo
	assert_not_null(mas_alto)

	var medio_ancho: float = _extent(mas_alto).x * 0.5
	assert_lte(absf(mas_alto.position.x) + medio_ancho, RoomScaffold.OPENING_WIDTH * 0.5 + 0.5,
			"el último peldaño cabe dentro de la columna del hueco, no bajo el techo")


func test_ninguna_sala_de_las_zonas_avisa_de_configuracion() -> void:
	for escena: PackedScene in [VerdantScene, CinderScene]:
		var zona: Zone = escena.instantiate() as Zone
		add_child_autofree(zona)
		await get_tree().process_frame
		for nodo in zona.find_children("*", "RoomScaffold", true, false):
			var scaffold := nodo as RoomScaffold
			assert_eq(scaffold._get_configuration_warnings().size(), 0,
					"'%s' avisa: %s" % [scaffold.get_parent().name,
					scaffold._get_configuration_warnings()])


## --- Recorrido real: un jugador subiendo la escalera ---

func test_el_jugador_sube_la_escalera_de_verdad() -> void:
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.TOP)
	h.setup(Vector2.ZERO, Vector2(4000, 0), false)
	scaffold.reparent(h)

	var jugador := h.sword_player
	jugador.place_at(Vector2(0.0, scaffold.floor_surface_y() - 4.0))
	await h.tick_physics(20)
	assert_true(jugador.is_on_floor(), "el jugador arranca de pie en el suelo de la sala")

	var partida := jugador.global_position.y
	var mejor := partida
	var direccion := 1.0
	for _i in range(600):
		await get_tree().physics_frame
		mejor = minf(mejor, jugador.global_position.y)
		if not jugador.is_on_floor():
			continue
		# Los peldaños alternan de lado, así que al aterrizar se cambia de
		# sentido y se vuelve a saltar. No hace falta piloto más listo.
		h.sword_input.set_move(direccion)
		h.sword_input.press_jump()
		direccion = -direccion

	var subido := partida - mejor
	var por_peldano := 1280.0 / float(scaffold._step_count())
	gut.p("subió %.0f px (%.1f peldaños de %.1f px)" % [subido, subido / por_peldano, por_peldano])
	assert_gt(subido, por_peldano * 3.0,
			"conduciendo a un jugador real se sube la escalera; " +
			"si se atasca en el primer peldaño, la sala no es escalable")


func test_se_sale_de_la_primera_sala_por_donde_aparecen_los_jugadores() -> void:
	# El recorrido exacto que estaba roto: los jugadores aparecían en
	# verdant_1, cuya única salida es el hueco de la derecha, y el hueco estaba
	# a 514 px del suelo. Se caía dentro y ahí se acababa la partida.
	var zona := VerdantScene.instantiate() as Zone
	add_child_autofree(zona)
	await get_tree().process_frame

	h.setup(Vector2.ZERO, Vector2(6000.0, 0.0), false)
	var jugador := h.sword_player
	jugador.place_at(zona.arrival_point())

	var sala := zona.room(&"verdant_1")
	var borde: float = sala.world_rect().end.x

	for _i in range(240):
		await get_tree().physics_frame
		h.sword_input.set_move(1.0)
		if jugador.is_on_floor() and jugador.velocity.x < 8.0:
			h.sword_input.press_jump()   ## por si tropieza con un peldaño
		if jugador.global_position.x > borde:
			break

	gut.p("llegó a x=%.0f (la sala acaba en x=%.0f)" % [jugador.global_position.x, borde])
	assert_gt(jugador.global_position.x, borde,
			"caminando hacia la salida se llega a la sala vecina")


## --- Utilidades ---

func _scaffold_suelto(medida: Vector2, aberturas: int) -> RoomScaffold:
	var scaffold := ScaffoldScript.new() as RoomScaffold
	scaffold.openings = aberturas
	scaffold.size = medida
	add_child_autofree(scaffold)
	scaffold.size = medida   ## fuerza el rebuild ya dentro del árbol
	return scaffold


func _extent(cuerpo: StaticBody2D) -> Vector2:
	var forma := cuerpo.get_child(0) as CollisionShape2D
	return (forma.shape as RectangleShape2D).size


## Los peldaños son los cuerpos estrechos: las paredes ocupan todo el lado.
func _peldanos(scaffold: RoomScaffold) -> Array[StaticBody2D]:
	var encontrados: Array[StaticBody2D] = []
	for hijo in scaffold.get_children():
		var cuerpo := hijo as StaticBody2D
		if cuerpo == null:
			continue
		var medida := _extent(cuerpo)
		if medida.x <= RoomScaffold.PLATFORM_WIDTH and medida.y <= RoomScaffold.PLATFORM_THICKNESS:
			encontrados.append(cuerpo)
	return encontrados


func _subida_maxima(scaffold: RoomScaffold) -> float:
	var caras: Array[float] = []
	for peldano in _peldanos(scaffold):
		caras.append(peldano.position.y - _extent(peldano).y * 0.5)
	caras.sort()
	caras.reverse()   ## de abajo arriba

	var peor := 0.0
	var anterior := scaffold.floor_surface_y()
	for cara in caras:
		peor = maxf(peor, anterior - cara)
		anterior = cara
	return maxf(peor, anterior - scaffold.ceiling_surface_y())


func _tramo_de_pared_derecha(scaffold: RoomScaffold) -> StaticBody2D:
	for hijo in scaffold.get_children():
		var cuerpo := hijo as StaticBody2D
		if cuerpo != null and cuerpo.position.x > scaffold.size.x * 0.4:
			return cuerpo
	return null


func _medir_altura_de_salto() -> float:
	await h.settle_on_floor()
	var partida := h.sword_player.global_position.y
	h.sword_input.press_jump()
	h.sword_input.set_jump_held(true)
	var mejor := partida
	for _i in range(90):
		await get_tree().physics_frame
		mejor = minf(mejor, h.sword_player.global_position.y)
	h.sword_input.release_all()
	return partida - mejor


func _medir_alcance_horizontal() -> float:
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await h.tick_physics(40)   ## carrerilla hasta velocidad de crucero

	var partida := h.sword_player.global_position
	h.sword_input.press_jump()
	h.sword_input.set_jump_held(true)
	var alcance := 0.0
	var despego := false
	for _i in range(90):
		await get_tree().physics_frame
		var jugador := h.sword_player
		if not jugador.is_on_floor():
			despego = true
			alcance = jugador.global_position.x - partida.x
		elif despego:
			break   ## ya aterrizó: lo que corra después no es alcance de salto
	h.sword_input.release_all()
	return alcance
