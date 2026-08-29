extends GutTest

## El lobby: la puerta de entrada, y hasta ahora el único sistema de producción
## sin una sola prueba.
##
## Lo que de verdad se cubre aquí es un aviso que no llega por señal. Cuando la
## sesión muere EN PARTIDA, quien la termina cambia de escena, y el lobby que
## aparece se suscribe a `session_ended` después de que se emitiera: nunca la ve.
## El síntoma era volver al lobby tras una desconexión y encontrarse un saludo
## como si no hubiera pasado nada. Por eso el motivo se recoge del
## `NetworkManager` al montarse, y por eso el caso de abajo monta el lobby DESPUÉS
## de que la sesión muera — montarlo antes lo recogería por señal y estaría
## probando el otro camino.
##
## Estos tests tocan los autoloads de verdad, que no tienen doble: es el lobby
## real el que los usa. Medido inocuo — `reset()` solo cambia un
## `OfflineMultiplayerPeer` por otro en el árbol principal, y los tests de red
## corren bajo sus propias `MultiplayerAPI` en subárboles aparte.

const LobbyScene := preload("res://systems/network/lobby.tscn")

var lobby: Control


func before_all() -> void:
	# Si alguien lanzara la suite con `-- --host`, `_apply_command_line` abriría
	# el puerto de verdad y estos tests dejarían de probar lo que dicen.
	assert_true(OS.get_cmdline_user_args().is_empty(),
			"la suite no debe llevar argumentos de usuario")


func after_each() -> void:
	# Que un motivo sin consumir no se cuele en el test siguiente.
	NetworkManager.consume_end_reason()
	NetworkManager.reset()


func test_recien_montado_saluda_y_deja_los_botones_libres() -> void:
	lobby = _montar()

	assert_eq(_rotulo(), "Hospeda una partida o únete a una.")
	assert_false(_boton("HostButton").disabled)
	assert_false(_boton("JoinButton").disabled)


func test_un_lobby_nuevo_cuenta_por_que_murio_la_sesion_anterior() -> void:
	# El orden es el del fallo real: la sesión muere ANTES de que exista este
	# lobby. Si se monta antes, lo recoge por señal y el test no prueba nada.
	await _matar_sesion("el otro jugador se desconectó")

	lobby = _montar()

	assert_eq(_rotulo(), "Sesión terminada: el otro jugador se desconectó.",
			"el motivo lo trae `consume_end_reason()`, no la señal: ya se emitió")
	assert_false(_boton("HostButton").disabled,
			"y se puede volver a jugar en el acto")


func test_el_motivo_se_cuenta_una_sola_vez() -> void:
	await _matar_sesion("se perdió la conexión con el host")

	lobby = _montar()
	assert_eq(_rotulo(), "Sesión terminada: se perdió la conexión con el host.",
			"si esto falla, el caso de abajo no prueba nada")

	# Volver al lobby más tarde no debe repetir un aviso ya contado.
	var segundo := _montar()
	assert_eq(_rotulo(segundo), "Hospeda una partida o únete a una.")


func test_la_sesion_que_muere_estando_aqui_tambien_se_explica() -> void:
	lobby = _montar()
	lobby._set_busy("Esperando al otro jugador…")

	await _matar_sesion("el otro jugador no terminó de cargar la partida")

	assert_eq(_rotulo(), "Sesión terminada: el otro jugador no terminó de cargar la partida.")
	assert_false(_boton("HostButton").disabled,
			"los botones vuelven, o el lobby queda muerto sin decir por qué")


func test_un_error_de_conexion_devuelve_los_botones() -> void:
	lobby = _montar()
	lobby._set_busy("Conectando…")

	NetworkManager.connection_error.emit("No se pudo conectar a 10.0.0.1:4242.")
	await get_tree().process_frame

	assert_eq(_rotulo(), "No se pudo conectar a 10.0.0.1:4242.")
	assert_false(_boton("JoinButton").disabled)
	assert_true(_boton("IpField").editable)


func test_esc_cancela_la_espera() -> void:
	# Sin esto, hospedar y que no venga nadie era un callejón sin salida: los dos
	# botones deshabilitados, `create_server` sin expirar y ninguna forma de salir.
	lobby = _montar()
	assert_eq(NetworkManager.host(), OK, "hace falta el puerto libre")
	lobby._set_busy("Esperando al otro jugador…")
	assert_true(NetworkManager.is_active)

	_pulsar_escape()
	await get_tree().process_frame

	assert_false(NetworkManager.is_active, "cancelar cierra la sesión")
	assert_false(_boton("HostButton").disabled, "y devuelve los botones")
	assert_eq(_rotulo(), "Se canceló la espera.")
	assert_eq(NetworkManager.consume_end_reason(), "",
			"cancelar no es un final que haya que explicar después")


func test_esc_sin_sesion_no_hace_nada() -> void:
	lobby = _montar()

	_pulsar_escape()
	await get_tree().process_frame

	assert_eq(_rotulo(), "Hospeda una partida o únete a una.",
			"sin nada que cancelar, Esc no debe ensuciar el rótulo")


## Mata la sesión por el camino involuntario, que es el único que deja motivo.
func _matar_sesion(reason: String) -> void:
	NetworkManager.is_active = true
	NetworkManager._end_session(reason)
	await get_tree().process_frame
	await get_tree().process_frame


func _montar() -> Control:
	var nodo := LobbyScene.instantiate() as Control
	add_child_autofree(nodo)
	return nodo


func _pulsar_escape() -> void:
	var evento := InputEventAction.new()
	evento.action = &"ui_cancel"
	evento.pressed = true
	get_tree().root.push_input(evento)


func _rotulo(desde: Control = null) -> String:
	var nodo := desde if desde != null else lobby
	var etiqueta := nodo.get_node("%StatusLabel") as Label
	return etiqueta.text


func _boton(nombre: String) -> Control:
	return lobby.get_node("%%%s" % nombre) as Control
