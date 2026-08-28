extends GutTest

## Combate asimétrico: la espada conecta, el escudo bloquea, el parry se
## distingue del bloqueo normal.
##
## Estos tests montan volúmenes sueltos en vez de personajes completos: lo que
## se prueba es el contrato hitbox / hurtbox / guardia, que es la pieza que el
## proyecto anterior nunca tuvo (allí el daño salía de la velocidad de choque).

const HitboxScript := preload("res://components/hitbox.gd")
const HurtboxScript := preload("res://components/hurtbox.gd")
const GuardBoxScript := preload("res://components/guard_box.gd")

const LAYER_PLAYER_HITBOX := 1 << 3
const LAYER_ENEMY_HURTBOX := 1 << 6
const LAYER_GUARD := 1 << 7


func _make_hitbox(layer: int, mask: int) -> Hitbox:
	var box := HitboxScript.new() as Hitbox
	box.collision_layer = layer
	box.collision_mask = mask
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	box.add_child(shape)
	add_child_autofree(box)
	return box


func _make_hurtbox(layer: int) -> Hurtbox:
	var box := HurtboxScript.new() as Hurtbox
	box.collision_layer = layer
	box.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	box.add_child(shape)
	add_child_autofree(box)
	return box


func _make_guard(layer: int) -> GuardBox:
	var box := GuardBoxScript.new() as GuardBox
	box.collision_layer = layer
	box.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	box.add_child(shape)
	add_child_autofree(box)
	return box


func test_la_hitbox_nace_apagada() -> void:
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_ENEMY_HURTBOX)
	await get_tree().physics_frame
	assert_false(hitbox.is_active(),
			"una hitbox solo se enciende durante los frames activos del ataque")


func test_enable_y_disable_controlan_la_ventana_activa() -> void:
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_ENEMY_HURTBOX)
	await get_tree().physics_frame

	hitbox.enable()
	assert_true(hitbox.is_active(), "enable() abre la ventana")

	hitbox.disable()
	assert_false(hitbox.is_active(), "disable() la cierra")


func test_la_hitbox_activa_golpea_una_hurtbox_solapada() -> void:
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_ENEMY_HURTBOX)
	var hurtbox := _make_hurtbox(LAYER_ENEMY_HURTBOX)
	hitbox.global_position = Vector2.ZERO
	hurtbox.global_position = Vector2.ZERO

	watch_signals(hitbox)
	hitbox.enable()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_signal_emitted(hitbox, "hit", "una hitbox activa sobre una hurtbox conecta")


func test_la_hitbox_apagada_no_golpea() -> void:
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_ENEMY_HURTBOX)
	var hurtbox := _make_hurtbox(LAYER_ENEMY_HURTBOX)
	hitbox.global_position = Vector2.ZERO
	hurtbox.global_position = Vector2.ZERO

	watch_signals(hitbox)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_signal_not_emitted(hitbox, "hit",
			"sin enable() el arma atraviesa sin dañar")


func test_max_targets_limita_las_victimas_por_activacion() -> void:
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_ENEMY_HURTBOX)
	hitbox.max_targets = 1
	var a := _make_hurtbox(LAYER_ENEMY_HURTBOX)
	var b := _make_hurtbox(LAYER_ENEMY_HURTBOX)
	hitbox.global_position = Vector2.ZERO
	a.global_position = Vector2.ZERO
	b.global_position = Vector2(5, 0)

	watch_signals(hitbox)
	hitbox.enable()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(get_signal_emit_count(hitbox, "hit"), 1,
			"con max_targets = 1 solo una víctima por golpe")


func test_la_guardia_levantada_bloquea() -> void:
	var guard := _make_guard(LAYER_GUARD)
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_GUARD)
	await get_tree().physics_frame

	guard.global_position = Vector2.ZERO
	hitbox.global_position = Vector2(20, 0)
	guard.raise(1)   ## Mira a la derecha, de donde viene el golpe.

	watch_signals(guard)
	hitbox.enable()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_signal_emitted(guard, "blocked", "la guardia frontal intercepta el golpe")


func test_la_guardia_bajada_no_bloquea() -> void:
	var guard := _make_guard(LAYER_GUARD)
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_GUARD)
	await get_tree().physics_frame

	guard.global_position = Vector2.ZERO
	hitbox.global_position = Vector2(20, 0)
	guard.lower()

	watch_signals(guard)
	hitbox.enable()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_signal_not_emitted(guard, "blocked")


func test_bloquear_al_instante_es_parry() -> void:
	var guard := _make_guard(LAYER_GUARD)
	await get_tree().physics_frame
	guard.raise(1)

	assert_true(guard.is_in_parry_window(),
			"nada más levantar la guardia se está en ventana de parry")


func test_la_ventana_de_parry_expira() -> void:
	var guard := _make_guard(LAYER_GUARD)
	guard.parry_window = 0.05
	await get_tree().physics_frame
	guard.raise(1)

	await wait_seconds(0.15)

	assert_true(guard.is_raised(), "la guardia sigue alta")
	assert_false(guard.is_in_parry_window(),
			"pero pasada la ventana ya es bloqueo normal, no parry")


func test_la_guardia_no_cubre_por_la_espalda() -> void:
	var guard := _make_guard(LAYER_GUARD)
	var hitbox := _make_hitbox(LAYER_PLAYER_HITBOX, LAYER_GUARD)
	await get_tree().physics_frame

	guard.global_position = Vector2.ZERO
	hitbox.global_position = Vector2(-20, 0)   ## Golpe por detrás.
	guard.raise(1)                              ## Mirando a la derecha.

	watch_signals(guard)
	hitbox.enable()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_signal_not_emitted(guard, "blocked",
			"un escudo frontal no protege la espalda")


func test_girarse_mientras_bloquea_no_reabre_el_parry() -> void:
	var guard := _make_guard(LAYER_GUARD)
	guard.parry_window = 0.05
	await get_tree().physics_frame

	guard.raise(1)
	await wait_seconds(0.12)
	assert_false(guard.is_in_parry_window(), "la ventana ya expiró")

	guard.set_facing(-1)
	assert_false(guard.is_in_parry_window(),
			"cambiar de lado no debe regalar una ventana de parry nueva")


## --- Dirección del empuje ---

func test_el_empuje_a_bocajarro_sigue_al_dueño_volteado() -> void:
	# A quemarropa no hay vector entre cuerpos del que fiarse, así que la
	# hitbox recurre a hacia dónde mira. `scale.x` es la escala LOCAL (siempre
	# 1) y `global_scale.x` pierde el signo al descomponer la transform: con
	# cualquiera de las dos, un golpe pegado empujaba siempre a la derecha.
	var dueño := Node2D.new()
	add_child_autofree(dueño)
	dueño.scale.x = -1.0

	var hitbox := HitboxScript.new() as Hitbox
	dueño.add_child(hitbox)
	var víctima := Node2D.new()
	add_child_autofree(víctima)
	await get_tree().process_frame

	hitbox.global_position = Vector2(100.0, 0.0)
	víctima.global_position = Vector2(100.0, 0.0)   ## alineados en X

	assert_lt(hitbox.direction_to(víctima).x, 0.0,
			"con el dueño volteado el empuje sale hacia la izquierda")
