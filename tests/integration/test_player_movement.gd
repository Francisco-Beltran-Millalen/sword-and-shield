extends GutTest

## Movimiento del jugador sobre la escena real: gravedad, salto, coyote time y
## buffer de salto. Es el test que guarda el *game feel* — si alguien rompe la
## sensación del salto, cae aquí.

const Harness := preload("res://tests/integration/_harness.gd")

var h: IntegrationHarness


func before_each() -> void:
	h = Harness.new()
	add_child(h)
	h.setup()


func after_each() -> void:
	h.teardown()


func test_el_jugador_cae_y_aterriza() -> void:
	await h.settle_on_floor()
	assert_true(h.sword_player.is_on_floor(), "el jugador debe aterrizar sobre el suelo")


func test_moverse_a_la_derecha_gana_velocidad_positiva() -> void:
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await h.tick_physics(10)

	assert_gt(h.sword_player.velocity.x, 50.0, "moverse a la derecha acelera en +x")
	assert_eq(h.sword_player.get_facing(), 1, "y el jugador mira a la derecha")


func test_moverse_a_la_izquierda_invierte_el_encaramiento() -> void:
	await h.settle_on_floor()
	h.sword_input.set_move(-1.0)
	await h.tick_physics(10)

	assert_lt(h.sword_player.velocity.x, -50.0)
	assert_eq(h.sword_player.get_facing(), -1)


func test_la_friccion_frena_al_soltar() -> void:
	await h.settle_on_floor()
	h.sword_input.set_move(1.0)
	await h.tick_physics(20)
	h.sword_input.set_move(0.0)
	await h.tick_physics(30)

	assert_almost_eq(h.sword_player.velocity.x, 0.0, 20.0,
			"sin entrada el jugador se detiene")


func test_saltar_despega_del_suelo() -> void:
	await h.settle_on_floor()
	var ground_y := h.sword_player.global_position.y

	h.sword_input.press_jump()
	await h.tick_physics(12)

	assert_lt(h.sword_player.global_position.y, ground_y - 20.0,
			"tras saltar el jugador está más arriba")


func test_no_hay_doble_salto_sin_la_habilidad() -> void:
	await h.settle_on_floor()
	h.sword_input.press_jump()
	await h.tick_physics(15)

	var height_before := h.sword_player.global_position.y
	var vy_before := h.sword_player.velocity.y
	h.sword_input.press_jump()
	await h.tick_physics(2)

	assert_gt(h.sword_player.velocity.y, vy_before - 10.0,
			"un segundo salto en el aire no debe impulsar sin AIR_JUMPS")
	assert_not_null(height_before)


func test_el_doble_salto_funciona_al_desbloquearlo() -> void:
	# Desbloquear una habilidad = colgar un modificador del StatsComponent,
	# sin tocar ni una línea del jugador.
	h.sword_player.stats.add_child(AbilityUnlock.air_jumps(1.0))
	await h.settle_on_floor()
	assert_eq(h.sword_player.stats.get_stat_int(StatsComponent.StatID.AIR_JUMPS), 1)

	h.sword_input.press_jump()
	await h.tick_physics(20)
	var vy_before := h.sword_player.velocity.y

	h.sword_input.press_jump()
	await h.tick_physics(2)

	assert_lt(h.sword_player.velocity.y, vy_before,
			"con AIR_JUMPS=1 el segundo salto sí impulsa")


func test_el_buffer_recuerda_el_salto_pulsado_antes_de_aterrizar() -> void:
	await h.settle_on_floor()
	h.sword_player.place_at(Vector2(0.0, -60.0))
	await h.tick_physics(2)

	# Pulsar el salto en el aire, poco antes de tocar suelo.
	h.sword_input.press_jump()
	await h.tick_physics(1)
	h.sword_input.set_jump_held(true)

	await h.tick_physics(20)
	assert_lt(h.sword_player.global_position.y, 20.0,
			"el salto se ejecuta al aterrizar gracias al buffer")
