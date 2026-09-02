extends GutTest

## Profundidad del graybox: las capas de fondo y de primer plano, y el orden en
## que se pinta el mundo.
##
## Existe por un defecto que estuvo en el repo sin que nadie lo viera: con cero
## `z_index` en producción, el orden de dibujo era el orden del árbol, y los
## enemigos de dos salas de Verdant se declaraban ANTES que su propio andamio.
## La geometría los tapaba. Ninguna prueba podía cazarlo porque ninguna miraba
## el dibujo — sólo la colisión.
##
## Lo que se afirma aquí es el CONTRATO de capas, no una estética: qué se pinta
## delante de qué, y que nada del decorado colisione.

const VerdantScene := preload("res://level/zones/zone_verdant.tscn")
const CinderScene := preload("res://level/zones/zone_cinder.tscn")
const PlayerScene := preload("res://characters/player/player.tscn")
const WorldScene := preload("res://systems/world/world.tscn")

## Las dos zonas se montan SIEMPRE juntas. Cuando algo se configura por datos, un
## solo caso no prueba nada: con una única zona, una paleta compartida por error
## se ve idéntica a una paleta bien repartida. Es la figura del fallo de los
## sub-recursos compartidos del enemigo, que sólo había un arquetipo.
var _zonas: Array[Zone] = []


func before_each() -> void:
	_zonas = []
	for escena: PackedScene in [VerdantScene, CinderScene]:
		var zona := escena.instantiate() as Zone
		add_child_autofree(zona)
		_zonas.append(zona)


## --- Las capas existen ---

func test_cada_zona_tiene_fondo_y_primer_plano() -> void:
	for zona in _zonas:
		var fondo := _capas_de_fondo(zona)
		var frente := _capas_de_frente(zona)
		assert_gt(fondo.size(), 0,
				"'%s' no tiene ninguna capa de fondo: el nivel es plano" % zona.zone_id)
		assert_gt(frente.size(), 0,
				"'%s' no tiene ninguna capa de primer plano" % zona.zone_id)


func test_las_capas_de_fondo_se_mueven_menos_que_el_mundo() -> void:
	# Es lo que las hace fondo. Un `scroll_scale` de 1 sería decorado pegado a la
	# sala, no profundidad.
	for zona in _zonas:
		for capa in _capas_de_fondo(zona):
			assert_lt(capa.scroll_scale.x, 1.0, "%s debe rezagarse en X" % capa.name)
			assert_lt(capa.scroll_scale.y, 1.0, "%s debe rezagarse en Y" % capa.name)


func test_el_primer_plano_se_mueve_mas_que_el_mundo() -> void:
	for zona in _zonas:
		for capa in _capas_de_frente(zona):
			assert_gt(capa.scroll_scale.x, 1.0, "%s debe adelantarse en X" % capa.name)


## --- El decorado no es sólido ---

func test_ninguna_capa_de_profundidad_colisiona() -> void:
	# Un fondo con cuerpo convierte el paisaje en pared. Y no se vería hasta que
	# alguien se quedara atascado en mitad de la sala.
	for zona in _zonas:
		for capa in _capas_de_fondo(zona) + _capas_de_frente(zona):
			var cuerpos := capa.find_children("*", "CollisionObject2D", true, false)
			assert_eq(cuerpos.size(), 0,
					"'%s' de '%s' tiene %d cuerpos: el decorado no colisiona"
					% [capa.name, zona.zone_id, cuerpos.size()])


## --- El orden de dibujo ---

func test_el_fondo_queda_detras_de_la_geometria() -> void:
	for zona in _zonas:
		var solidos := _z_del_andamio(zona)
		for capa in _capas_de_fondo(zona):
			assert_lt(capa.z_index, solidos,
					"%s (z=%d) debe quedar detrás de los sólidos (z=%d)"
					% [capa.name, capa.z_index, solidos])


func test_la_geometria_queda_detras_de_las_entidades() -> void:
	# El defecto original: el andamio se pintaba sobre sus propios enemigos.
	var jugador := PlayerScene.instantiate() as Player
	add_child_autofree(jugador)
	for zona in _zonas:
		assert_lt(_z_del_andamio(zona), jugador.z_index,
				"la geometría de '%s' no puede taparle a nadie" % zona.zone_id)


func test_el_primer_plano_queda_delante_de_las_entidades() -> void:
	var jugador := PlayerScene.instantiate() as Player
	add_child_autofree(jugador)
	for zona in _zonas:
		for capa in _capas_de_frente(zona):
			assert_gt(capa.z_index, jugador.z_index,
					"%s tiene que pasar POR DELANTE del personaje" % capa.name)


func test_las_marcas_de_andamio_no_tapan_a_las_entidades() -> void:
	# Borde de sala y marco de puerta son ayudas de depuración: van por encima de
	# la geometría y por debajo de quien juega.
	var jugador := PlayerScene.instantiate() as Player
	add_child_autofree(jugador)
	for zona in _zonas:
		var solidos := _z_del_andamio(zona)
		for sala in zona.rooms():
			assert_gt(sala.z_index, solidos, "el borde de '%s' se lee sobre el suelo" % sala.room_id)
			assert_lt(sala.z_index, jugador.z_index,
					"el borde de '%s' no puede taparle a nadie" % sala.room_id)
		for puerta in zona.doors():
			assert_lt(puerta.z_index, jugador.z_index,
					"el marco de '%s' no puede tapar a quien la cruza" % puerta.door_id)


func test_el_z_index_de_las_capas_es_absoluto() -> void:
	# Con `z_as_relative` el valor se suma al del padre, así que un `z_index`
	# puesto en un contenedor desplazaría el contrato entero sin avisar.
	for zona in _zonas:
		for capa in _capas_de_fondo(zona) + _capas_de_frente(zona):
			assert_false(capa.z_as_relative, "%s debe fijar su capa, no heredarla" % capa.name)


## --- La paleta dice las reglas ---

func test_los_cuatro_roles_de_la_sala_tienen_colores_distintos() -> void:
	# Sobre todo la losa: es la única pieza que se ATRAVIESA, y pintarla como el
	# suelo deja la regla más importante de la sala sin comunicar.
	for zona in _zonas:
		for nodo in zona.find_children("*", "RoomScaffold", true, false):
			var andamio := nodo as RoomScaffold
			assert_not_null(andamio, "el nodo debe conservar su script")
			var vistos := {
				andamio.floor_color: true, andamio.wall_color: true,
				andamio.ceiling_color: true, andamio.platform_color: true,
			}
			assert_eq(vistos.size(), 4,
					"'%s' repite color entre suelo, pared, techo y losa" % zona.zone_id)


func test_las_dos_zonas_no_se_pintan_igual() -> void:
	# Diez salas idénticas y dos zonas idénticas: nada en pantalla decía dónde
	# estabas. Se separan por el fondo, que es lo que ocupa la pantalla entera.
	var paletas: Array[Color] = []
	for zona in _zonas:
		var fondo := _capas_de_fondo(zona)
		assert_gt(fondo.size(), 0)
		var pieza := fondo[0].get_child(0) as Polygon2D
		assert_not_null(pieza, "una capa de fondo sin nada dibujado no es un fondo")
		paletas.append(pieza.color)
	assert_ne(paletas[0], paletas[1], "verdant y cinder no pueden tener el mismo fondo")


func test_el_fondo_es_mas_oscuro_que_la_geometria() -> void:
	# La escala de luminancia es la que da la profundidad: cuanto más lejos, más
	# hundido. Antes estaba del revés — el vacío era el gris (0.3,0.3,0.3) por
	# defecto de Godot y los sólidos, más oscuros que él.
	for zona in _zonas:
		var andamio := (zona.find_children("*", "RoomScaffold", true, false)[0]) as RoomScaffold
		var techo := _luminancia(andamio.ceiling_color)
		for capa in _capas_de_fondo(zona):
			var pieza := capa.get_child(0) as Polygon2D
			assert_lt(_luminancia(pieza.color), techo,
					"%s se lee tan cerca como la geometría" % capa.name)


## --- Utilidades ---

## Se buscan por TIPO y por su papel (cuánto se rezagan), no por nombre: añadir
## una tercera capa de fondo no debe obligar a tocar el test.
func _capas_de_fondo(zona: Zone) -> Array[Parallax2D]:
	return _capas(zona, true)


func _capas_de_frente(zona: Zone) -> Array[Parallax2D]:
	return _capas(zona, false)


func _capas(zona: Zone, rezagadas: bool) -> Array[Parallax2D]:
	var encontradas: Array[Parallax2D] = []
	for nodo in zona.find_children("*", "Parallax2D", true, false):
		var capa := nodo as Parallax2D
		if capa == null:
			continue
		if (capa.scroll_scale.x < 1.0) == rezagadas:
			encontradas.append(capa)
	return encontradas


func _z_del_andamio(zona: Zone) -> int:
	var andamios := zona.find_children("*", "RoomScaffold", true, false)
	assert_gt(andamios.size(), 0, "la zona debe tener geometría")
	return (andamios[0] as Node2D).z_index


func _luminancia(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


## --- Que los nodos de la escena CONSERVEN su script ---

func test_todo_lo_que_monta_el_world_conserva_su_script() -> void:
	# Un error de parseo deja al nodo SIN script y la escena se instancia igual:
	# es la trampa que este proyecto lleva nueve veces sufriendo, y la novena fue
	# el propio overlay de depuración —`NOTIFICATION_VISIBILITY_CHANGED` no existe
	# en un `CanvasLayer`—, que sólo se vio lanzando el juego de verdad.
	#
	# Se comprueba sobre `world.tscn` y no sobre cada script suelto porque lo que
	# rompe es la ESCENA: `load()` de un script roto devuelve null y el `.tscn`
	# sigue cargando, tan contento.
	var mundo := WorldScene.instantiate()
	for ruta: String in ["Hud", "DebugOverlay"]:
		var nodo := mundo.get_node_or_null(ruta)
		assert_not_null(nodo, "el World debe montar '%s'" % ruta)
		assert_not_null(nodo.get_script(),
				"'%s' se quedó SIN script: no compila y la escena carga igual" % ruta)
	mundo.free()


func test_el_overlay_no_conoce_a_nadie() -> void:
	# Su valor es no tener punteros a entidades: una zona que se descarga o un
	# jugador que se va no pueden dejarle nada muerto. Lo que sabe se lo empujan
	# (`set_zone`) o le llega por el bus.
	var mundo := WorldScene.instantiate()
	var overlay := mundo.get_node_or_null("DebugOverlay")
	assert_not_null(overlay)
	assert_true(overlay.has_method(&"set_zone"), "la zona se le empuja, no la consulta")
	assert_eq(overlay.get_child_count(), 1, "sólo su propia interfaz cuelga de él")
	mundo.free()
