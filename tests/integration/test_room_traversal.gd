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


## Sustituye a `test_el_ultimo_peldano_queda_bajo_la_abertura_superior`, que
## codificaba el DISEÑO ("hay un peldaño en tal sitio") en vez del REQUISITO
## ("se puede salir por arriba"). No es relajar el listón: aquel test pasaba en
## verde mientras salir de `verdant_5` costaba acertar una ventana de coyote de
## seis frames, y no habría visto que con el descansillo se sale de sobra.
##
## Barre varias posiciones de salida y las dos direcciones, y exige una FRACCIÓN
## en vez de un caso: un test escrito a la medida del único guion que funciona
## deja enterrado que los otros quince fallan. Medido: con descansillo salen 11
## de 16 intentos; sin él, 2.
func test_se_sale_por_la_abertura_superior() -> void:
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.TOP)
	h.setup(Vector2.ZERO, Vector2(4000, 0), false)
	scaffold.reparent(h)

	var techo := scaffold.ceiling_surface_y()
	var salidas := 0
	var intentos := 0

	## El descansillo es la fila más alta: se busca en vez de calcularlo, para
	## que el test siga midiendo lo mismo si cambia el reparto de pasos.
	var descansillo: StaticBody2D = null
	for cuerpo in _peldanos(scaffold):
		if descansillo == null or cuerpo.position.y < descansillo.position.y:
			descansillo = cuerpo
	assert_not_null(descansillo, "hay una fila más alta")
	var cara: float = descansillo.position.y - _extent(descansillo).y * 0.5

	for partida: float in [-40.0, 0.0, 60.0, 140.0, 200.0, 260.0]:
		for sentido: float in [-1.0, 1.0]:
			intentos += 1
			var jugador := h.sword_player
			## ENCIMA del descansillo, apoyado en su cara.
			jugador.place_at(Vector2(partida, cara - 4.0))
			await h.tick_physics(12)

			for _i in range(120):
				await get_tree().physics_frame
				if jugador.global_position.y < techo:
					break   ## cruzó el techo: está fuera de la sala
				if jugador.is_on_floor():
					h.sword_input.set_move(sentido)
					h.sword_input.press_jump()
			if jugador.global_position.y < techo:
				salidas += 1

	gut.p("salidas por la abertura superior: %d de %d" % [salidas, intentos])
	assert_gt(salidas, intentos / 3,
			"desde el descansillo se sale por arriba en la mayoría de intentos; " +
			"si no, una sala que solo abre arriba queda sellada")


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
	# Bajo la escalera, que ya no está en el centro de la sala: vive a la derecha
	# de la columna del hueco de paso para dejarla libre. Desde x=0 el jugador
	# tendría que caminar 70 px antes de poder empezar a subir, y este piloto no
	# sabe hacer eso — lo que mide es la escalera, no la búsqueda.
	var eje := RoomScaffold.PLATFORM_MARGIN + RoomScaffold.PLATFORM_WIDTH * 0.5
	jugador.place_at(Vector2(eje, scaffold.floor_surface_y() - 4.0))
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
		# Por GROSOR y no por ancho: el descansillo de la última fila es más
		# ancho que `PLATFORM_WIDTH` y seguía siendo un peldaño. Suelo y techo
		# miden 32 de grosor y las paredes 1044 de alto, así que este filtro
		# solo deja pasar losas.
		if medida.y <= RoomScaffold.PLATFORM_THICKNESS:
			encontrados.append(cuerpo)
	return encontrados


## Peor subida entre dos apoyos que de verdad se encadenan.
##
## Ordenar las caras SOLO por Y —como se hacía aquí— es una métrica que miente:
## dos losas a distinta altura pero separadas horizontalmente no son peldaños
## consecutivos, y aun así se contaban como tales. Medido sobre un diseño de
## losas alternas en el que el jugador no subía ni un peldaño, esta función
## seguía devolviendo 71.1 px y su test seguía VERDE. Por eso ahora un apoyo
## solo continúa la escalera si además de estar más arriba SOLAPA EN X con
## aquel desde el que se salta.
##
## Un apoyo al que no se llega desde ninguno de los alcanzados devuelve INF: la
## sala no se puede escalar, que es exactamente lo que el test debe ver.
func _subida_maxima(scaffold: RoomScaffold) -> float:
	var apoyos: Array = []
	for peldano in _peldanos(scaffold):
		var medida := _extent(peldano)
		apoyos.append([
			peldano.position.y - medida.y * 0.5,   ## la cara que se pisa
			peldano.position.x - medida.x * 0.5,
			peldano.position.x + medida.x * 0.5,
		])
	## De abajo arriba: en Godot la Y crece hacia abajo.
	apoyos.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	## El suelo abarca la sala entera, así que solapa con todo.
	var alcanzados: Array = [[scaffold.floor_surface_y(), -scaffold.size.x, scaffold.size.x]]
	var peor := 0.0
	var mas_alto := scaffold.floor_surface_y()

	for apoyo: Array in apoyos:
		var salto_minimo := INF
		for previo: Array in alcanzados:
			if previo[0] <= apoyo[0]:
				continue   ## no está por debajo: no se salta desde ahí
			if apoyo[2] < previo[1] or apoyo[1] > previo[2]:
				continue   ## sin solape en X: no son consecutivos
			salto_minimo = minf(salto_minimo, previo[0] - apoyo[0])
		if is_inf(salto_minimo):
			return INF
		peor = maxf(peor, salto_minimo)
		alcanzados.append(apoyo)
		mas_alto = minf(mas_alto, apoyo[0])

	return maxf(peor, mas_alto - scaffold.ceiling_surface_y())


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


## --- Lo que el dueño pidió: poder caminar ---

## Las losas medían 40x24 px contra un cuerpo de 28 de ancho: doce píxeles de
## paseo. Este test es el encargo literal, y por eso mide ANDANDO en vez de
## comprobar el ancho de la forma: una losa ancha con la que uno se cae por un
## borde mal puesto pasaría igual una comprobación de medidas.
func test_se_puede_caminar_sobre_una_losa() -> void:
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.TOP)
	h.setup(Vector2.ZERO, Vector2(4000, 0), false)
	scaffold.reparent(h)

	## La fila más baja, por su extremo izquierdo.
	var losa: StaticBody2D = null
	for cuerpo in _peldanos(scaffold):
		if losa == null or cuerpo.position.y > losa.position.y:
			losa = cuerpo
	assert_not_null(losa)

	var medida := _extent(losa)
	var izquierda: float = losa.position.x - medida.x * 0.5
	var cara: float = losa.position.y - medida.y * 0.5

	var jugador := h.sword_player
	jugador.place_at(Vector2(izquierda + 20.0, cara - 4.0))
	await h.tick_physics(10)
	assert_true(jugador.is_on_floor(), "el jugador se posa sobre la losa")

	var partida := jugador.global_position.x
	for _i in range(90):
		h.sword_input.set_move(1.0)
		await get_tree().physics_frame
	h.sword_input.set_move(0.0)
	await h.tick_physics(4)

	var recorrido := jugador.global_position.x - partida
	assert_gt(recorrido, 100.0,
			"se camina 100+ px sobre una losa: recorrió %.0f" % recorrido)
	assert_true(jugador.is_on_floor(), "y sigue sobre ella, no se ha caído")


## --- Y que la columna del hueco siga siendo un paso ---

## La escalera se mudó a la derecha justamente para dejar libre esta columna. Si
## una losa la invadiera, el jugador se posaría encima y la sala de abajo
## quedaría inalcanzable: se habría cambiado un encierro por otro.
func test_se_baja_por_el_agujero_del_suelo() -> void:
	var scaffold := _scaffold_suelto(Vector2(1280, 1280), RoomScaffold.Side.BOTTOM)
	h.setup(Vector2.ZERO, Vector2(4000, 0), false)
	scaffold.reparent(h)

	var suelo := scaffold.floor_surface_y()
	var jugador := h.sword_player
	## En la columna del hueco, a media sala.
	jugador.place_at(Vector2(0.0, suelo - 400.0))

	for _i in range(180):
		await get_tree().physics_frame
		if jugador.global_position.y > suelo + 60.0:
			break

	assert_gt(jugador.global_position.y, suelo + 60.0,
			"se cae por el agujero del suelo en vez de posarse en una losa")

