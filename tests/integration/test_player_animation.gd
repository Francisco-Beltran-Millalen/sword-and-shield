extends GutTest

## El cuerpo del jugador se mueve de verdad.
##
## Escrito contra las trampas nº1, nº2 y nº9 de `CLAUDE.md` a la vez: que la
## escena instancie no prueba que los nodos conserven su script, y que exista un
## `AnimationPlayer` no prueba que sus pistas muevan algo — el combate ya se pasó
## un tiempo sin daño porque las animaciones estaban vacías y los tests de la
## `Hitbox` aislada pasaban igual.
##
## Por eso aquí no se comprueba "se llamó a travel": se mide la ROTACIÓN REAL de
## los huesos y la posición REAL de los polígonos, conduciendo a un jugador con
## el mismo `IntentSource` guionizado que usan los demás tests de integración.

const Harness := preload("res://tests/integration/_harness.gd")

## Los once huesos del muñeco, tal y como cuelgan de `Visuals`.
const HIP := "Skeleton/Hip"
const TORSO := "Skeleton/Hip/Torso"
const HUESOS: Array[String] = [
	HIP, TORSO,
	TORSO + "/Head",
	TORSO + "/ArmBack", TORSO + "/ArmBack/ForearmBack",
	TORSO + "/ArmFront", TORSO + "/ArmFront/ForearmFront",
	HIP + "/LegBack", HIP + "/LegBack/ShinBack",
	HIP + "/LegFront", HIP + "/LegFront/ShinFront",
]
## Articulaciones de segundo segmento que TIENEN que doblarse al andar. El
## antebrazo delantero no está: ese brazo se mantiene quieto a propósito porque
## sujeta el kit, que cuelga del `Player` y no de la mano.
const ARTICULACIONES: Array[String] = [
	TORSO + "/ArmBack/ForearmBack",
	HIP + "/LegBack/ShinBack", HIP + "/LegFront/ShinFront",
]
## Los dos pies, para medir el apoyo.
const PIES: Array[String] = [
	HIP + "/LegBack/ShinBack/ShinBackShape",
	HIP + "/LegFront/ShinFront/ShinFrontShape",
]

var h: IntegrationHarness


func before_each() -> void:
	h = Harness.new()
	add_child(h)
	h.setup()


func after_each() -> void:
	h.teardown()


# ---------------------------------------------------------------- estructura

func test_el_esqueleto_esta_montado_y_cada_bone_es_un_bone() -> void:
	var visuals: Node2D = h.sword_player.get_node("Visuals")
	assert_true(visuals.get_node_or_null("Skeleton") is Skeleton2D,
			"los visuales tienen que colgar de un Skeleton2D")
	for ruta in HUESOS:
		var hueso := visuals.get_node_or_null(ruta)
		assert_not_null(hueso, "falta el hueso '%s'" % ruta)
		assert_true(hueso is Bone2D, "'%s' tiene que ser un Bone2D" % ruta)


func test_ningun_nodo_del_jugador_se_quedo_sin_script() -> void:
	# Trampa nº9: un script que no compila deja al nodo SIN script y la escena
	# se instancia igual, así que la suite entera puede seguir en verde.
	var esperados := {
		".": "player.gd",
		"StateAnimationTree": "state_animation_tree.gd",
		"StateMachine": "state_machine.gd",
		"Kit": "sword_kit.gd",
	}
	for ruta: String in esperados:
		var nodo := h.sword_player.get_node_or_null(ruta)
		assert_not_null(nodo, "falta el nodo '%s'" % ruta)
		var script: Script = nodo.get_script()
		assert_not_null(script,
				"'%s' se quedó SIN script: su .gd no compila" % ruta)
		assert_true(script.resource_path.ends_with(esperados[ruta]),
				"'%s' lleva el script equivocado: %s" % [ruta, script.resource_path])


func test_el_arbol_de_animacion_esta_vivo_y_conoce_sus_poses() -> void:
	var tree := _tree()
	assert_not_null(tree, "falta el AnimationTree")
	assert_true(tree.active, "el AnimationTree tiene que estar activo")
	var raiz := tree.tree_root as AnimationNodeStateMachine
	assert_not_null(raiz, "§13 pide un AnimationNodeStateMachine, no un árbol suelto")
	for pose in ["idle", "walk", "jump", "fall", "hurt", "downed", "attack", "guard"]:
		assert_true(raiz.has_node(pose), "el grafo no conoce la pose '%s'" % pose)


# ---------------------------------------------------------------- proporción

func test_la_cabeza_mide_lo_mismo_que_el_resto_del_cuerpo() -> void:
	# Se mide sobre los polígonos reales, no sobre constantes del test.
	var cabeza := _caja([TORSO + "/Head/HeadShape"])
	var cuerpo := _caja([
		TORSO + "/TorsoShape",
		HIP + "/LegBack/ThighBackShape", HIP + "/LegBack/ShinBack/ShinBackShape",
		HIP + "/LegFront/ThighFrontShape", HIP + "/LegFront/ShinFront/ShinFrontShape",
	])
	assert_almost_eq(cabeza.size.y, cuerpo.size.y, 0.5,
			"proporción 1:1 — la cabeza (%.1f px) y el cuerpo (%.1f px) miden igual"
			% [cabeza.size.y, cuerpo.size.y])


func test_el_muneco_mide_los_mismos_44_px_de_siempre() -> void:
	var todo := _caja(_todas_las_piezas())
	assert_almost_eq(todo.size.y, 44.0, 0.5, "la altura no cambia: 44 px")
	assert_almost_eq(todo.end.y, 0.0, 0.5, "los pies siguen en el origen del cuerpo")
	# La caja de colisión mide 28 y no se ha tocado: el dibujo tiene que caber.
	assert_lte(todo.size.x, 28.0,
			"el muñeco (%.1f px de ancho) se sale de su caja de colisión" % todo.size.x)


# ---------------------------------------------------------------- movimiento

func test_las_pistas_mueven_los_huesos_de_verdad() -> void:
	# Trampa nº2: un AnimationPlayer vacío pasa cualquier test que sólo mire si
	# "está sonando". Aquí se compara la postura en dos instantes del ciclo.
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(12)
	var antes := _postura()
	await _avanzar(12)
	var despues := _postura()

	var movido := 0
	for i in antes.size():
		if absf(antes[i] - despues[i]) > 0.05:
			movido += 1
	assert_gt(movido, 2,
			"andando sólo se movieron %d huesos de %d: ¿pistas vacías?"
			% [movido, HUESOS.size()])


func test_la_pose_sigue_al_estado() -> void:
	await h.settle_on_floor()
	await _avanzar(4)
	assert_eq(_pose(), &"idle", "quieto en el suelo, el cuerpo respira")

	h.sword_input.set_move(1.0)
	await _avanzar(6)
	assert_eq(_pose(), &"walk", "andando, el cuerpo anda")

	h.sword_input.set_move(0.0)
	h.sword_input.press_jump()
	await _avanzar(6)
	assert_eq(_pose(), &"jump", "subiendo, el cuerpo salta")

	# Hasta que la velocidad vertical se invierte: entonces cae.
	for _i in range(90):
		await _avanzar(1)
		if _pose() == &"fall":
			break
	assert_eq(_pose(), &"fall", "bajando, el cuerpo cae")


func test_el_kit_manda_sobre_el_estado_al_atacar_y_al_guardar() -> void:
	# `KIT_ACTION` es UN estado para atacar y guardar: sin la pose que anuncia el
	# kit, el escudo haría el gesto de la espada.
	await h.settle_on_floor()
	h.sword_input.press_attack()
	await _avanzar(4)
	assert_eq(_pose(), &"attack", "la espada ataca")

	h.shield_input.set_guard(true)
	await _avanzar(4)
	assert_eq(_pose(h.shield_player), &"guard", "el escudo guarda")

	h.shield_input.set_guard(false)
	await _avanzar(20)
	assert_ne(_pose(h.shield_player), &"guard", "al soltar, la guardia baja")


func test_el_combo_rearranca_el_gesto_del_cuerpo() -> void:
	# El segundo golpe NO cambia de estado —sigue en KIT_ACTION— así que sin el
	# rearranque explícito el cuerpo se quedaría clavado en la pose final del
	# primero mientras el arma sí repite su gesto.
	#
	# El golpe encadenado se ENCOLA (`Attacker._chain_queued`) y no empieza hasta
	# que termina el que está sonando, así que no se mide dos frames después de
	# pulsar: se vigila el reloj de la pose durante todo el combo y se busca el
	# instante en que retrocede.
	await h.settle_on_floor()
	h.sword_input.press_attack()
	await _avanzar(6)
	h.sword_input.press_attack()

	var rearranques := 0
	var anterior := _tiempo_de_pose()
	for _i in range(48):
		await _avanzar(1)
		var ahora := _tiempo_de_pose()
		if _pose() == &"attack" and ahora < anterior - 0.01:
			rearranques += 1
		anterior = ahora

	assert_gt(rearranques, 0,
			"el segundo golpe del combo tiene que rearrancar la pose del cuerpo")


func test_mirar_a_la_izquierda_voltea_el_muneco_entero() -> void:
	await h.settle_on_floor()
	var derecha := _caja([TORSO + "/Head/Eye"]).get_center().x

	h.sword_input.set_move(-1.0)
	await _avanzar(6)
	var izquierda := _caja([TORSO + "/Head/Eye"]).get_center().x

	assert_gt(derecha, 0.0, "mirando a la derecha, el ojo va delante")
	assert_lt(izquierda, 0.0, "mirando a la izquierda, el ojo cambia de lado")


func test_la_cadera_y_el_torso_contra_rotan_al_andar() -> void:
	# Cadera y torso son huesos distintos justamente para esto: si giran juntos,
	# el muñeco pivota en bloque y no hay transferencia de peso que leer. Lo que
	# se mide es que la pelvis bascula MUCHO más que el tronco en el mundo.
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(10)

	var cadera: Array[float] = []
	var tronco: Array[float] = []
	for _i in range(40):
		await _avanzar(1)
		cadera.append(_hueso(HIP).rotation)
		tronco.append(_hueso(TORSO).global_rotation)

	# `Array.max()` devuelve Variant aunque el array esté tipado: sin el tipo
	# explícito el script no compila, y GUT omite en silencio lo que no compila.
	var recorrido_cadera: float = cadera.max() - cadera.min()
	var recorrido_tronco: float = tronco.max() - tronco.min()
	assert_gt(recorrido_cadera, 0.08,
			"la cadera tiene que bascular durante el ciclo (recorrió %.3f rad)"
			% recorrido_cadera)
	assert_lt(recorrido_tronco, recorrido_cadera,
			"el tronco (%.3f rad) tiene que moverse MENOS que la cadera (%.3f): eso es la contra-rotación"
			% [recorrido_tronco, recorrido_cadera])


func test_las_rodillas_y_los_codos_se_doblan() -> void:
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(10)

	var minimo: Dictionary = {}
	var maximo: Dictionary = {}
	for _i in range(40):
		await _avanzar(1)
		for ruta in ARTICULACIONES:
			var angulo := _hueso(ruta).rotation
			minimo[ruta] = minf(minimo.get(ruta, angulo), angulo)
			maximo[ruta] = maxf(maximo.get(ruta, angulo), angulo)

	for ruta in ARTICULACIONES:
		var recorrido: float = maximo[ruta] - minimo[ruta]
		assert_gt(recorrido, 0.2,
				"'%s' apenas se dobló (%.3f rad): el miembro es un palo rígido"
				% [ruta.get_file(), recorrido])


func test_la_cadera_sube_y_baja_con_el_paso() -> void:
	# El sube y baja NO es un rebote pegado encima: sale de que la pierna de
	# apoyo se estira y se dobla. Si desaparece, el andar se ve deslizado.
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(10)

	var alturas: Array[float] = []
	for _i in range(40):
		await _avanzar(1)
		alturas.append(_hueso(HIP).position.y)
	var recorrido: float = alturas.max() - alturas.min()
	assert_gt(recorrido, 0.8,
			"la cadera se quedó plana (%.2f px de recorrido)" % recorrido)


func test_los_pies_no_se_hunden_ni_flotan_al_andar() -> void:
	# La contrapartida de mover la cadera: si la cadena de la pierna no cuadra
	# con la altura de la pelvis, el muñeco anda medio enterrado o de puntillas.
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(10)

	for _i in range(30):
		await _avanzar(1)
		var mas_bajo := _caja(PIES).end.y
		# 1,2 px de margen y no más: con 2,5 el hundimiento que se veía en la
		# tira de fotogramas pasaba el test sin despeinarse.
		assert_almost_eq(mas_bajo, 0.0, 1.2,
				"el pie más bajo quedó a %.2f px del suelo del cuerpo" % mas_bajo)


func test_el_pie_apoyado_retrocede_respecto_al_cuerpo() -> void:
	# ESTE es el test que caza un ciclo invertido, y hace falta porque un muñeco
	# que anda de espaldas se ve perfectamente vivo: tiene rodillas, balanceo y
	# rebote de cadera, y pasa todos los tests anteriores. Lo que lo delata es el
	# pie que toca el suelo — si el ciclo va al derecho, ese pie se queda clavado
	# en el mundo y por tanto RETROCEDE respecto al cuerpo, que avanza. Si va al
	# revés, patina hacia adelante.
	#
	# Se mide en el marco del jugador y con el facing aplicado, así que la
	# afirmación vale igual andando hacia los dos lados.
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await _avanzar(16)

	var pistas: Dictionary = {PIES[0]: [], PIES[1]: []}
	for _i in range(40):
		await _avanzar(1)
		for pie in PIES:
			var caja := _caja([pie])
			pistas[pie].append(Vector2(
					caja.get_center().x * float(h.sword_player.get_facing()),
					caja.end.y))

	var comprobados := 0
	for pie: String in pistas:
		var racha := _racha_apoyada(pistas[pie])
		if racha.size() < 5:
			continue
		comprobados += 1
		var avance: float = racha[racha.size() - 1] - racha[0]
		assert_lt(avance, 0.0,
				"'%s' se desliza %.2f px HACIA ADELANTE mientras apoya: el ciclo va al revés"
				% [pie.get_file(), avance])
	assert_gt(comprobados, 0, "ningún pie llegó a apoyarse durante el ciclo")


# ------------------------------------------------------------------ ayudantes

## El `AnimationTree` del jugador corre en el bucle de FÍSICA (ver `player.tscn`),
## así que un frame de física es también un frame de animación y el test avanza
## a la misma cadencia que el juego.
func _avanzar(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


func _tree(jugador: Player = null) -> AnimationTree:
	var quien: Player = jugador if jugador != null else h.sword_player
	return quien.get_node_or_null("Visuals/AnimationTree") as AnimationTree


func _playback(jugador: Player = null) -> AnimationNodeStateMachinePlayback:
	var tree := _tree(jugador)
	if tree == null:
		return null
	return tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _pose(jugador: Player = null) -> StringName:
	var playback := _playback(jugador)
	return playback.get_current_node() if playback != null else &""


func _tiempo_de_pose(jugador: Player = null) -> float:
	var playback := _playback(jugador)
	return playback.get_current_play_position() if playback != null else -1.0


## La racha consecutiva más larga en la que ese pie estuvo tocando el suelo,
## devuelta como sus posiciones en X. Un pie en vuelo no dice nada del sentido.
func _racha_apoyada(muestras: Array) -> Array[float]:
	var mejor: Array[float] = []
	var actual: Array[float] = []
	for m: Vector2 in muestras:
		if m.y > -0.8:
			actual.append(m.x)
		else:
			if actual.size() > mejor.size():
				mejor = actual
			actual = []
	return actual if actual.size() > mejor.size() else mejor


func _hueso(ruta: String, jugador: Player = null) -> Bone2D:
	var quien: Player = jugador if jugador != null else h.sword_player
	return quien.get_node("Visuals").get_node(ruta) as Bone2D


## Todas las piezas dibujadas del muñeco, para medir su silueta.
func _todas_las_piezas() -> Array:
	return [
		TORSO + "/Head/HeadShape", TORSO + "/TorsoShape",
		TORSO + "/ArmBack/ArmBackShape",
		TORSO + "/ArmBack/ForearmBack/ForearmBackShape",
		TORSO + "/ArmFront/ArmFrontShape",
		TORSO + "/ArmFront/ForearmFront/ForearmFrontShape",
		HIP + "/LegBack/ThighBackShape", HIP + "/LegBack/ShinBack/ShinBackShape",
		HIP + "/LegFront/ThighFrontShape", HIP + "/LegFront/ShinFront/ShinFrontShape",
	]


## Rotación actual de cada hueso, en el orden de `HUESOS`.
func _postura(jugador: Player = null) -> Array[float]:
	var quien: Player = jugador if jugador != null else h.sword_player
	var visuals: Node2D = quien.get_node("Visuals")
	var valores: Array[float] = []
	for ruta in HUESOS:
		var hueso := visuals.get_node(ruta) as Bone2D
		valores.append(hueso.rotation)
	return valores


## Caja que ocupan esas piezas, en coordenadas del jugador.
func _caja(rutas: Array, jugador: Player = null) -> Rect2:
	var quien: Player = jugador if jugador != null else h.sword_player
	var visuals: Node2D = quien.get_node("Visuals")
	var caja := Rect2()
	var primera := true
	for ruta: String in rutas:
		var pieza := visuals.get_node(ruta) as Polygon2D
		assert_not_null(pieza, "falta la pieza '%s'" % ruta)
		for punto in pieza.polygon:
			# Por la transformada completa, no `global_position + punto`: el
			# origen de un `Polygon2D` no es el centro de su dibujo, y los huesos
			# rotan y se voltean por encima de él.
			var mundo: Vector2 = pieza.global_transform * punto
			var local: Vector2 = mundo - quien.global_position
			if primera:
				caja = Rect2(local, Vector2.ZERO)
				primera = false
			else:
				caja = caja.expand(local)
	return caja
