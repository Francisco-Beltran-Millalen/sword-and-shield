extends GutTest

## El flujo completo del ataque: intención → animación → ventana de daño.
##
## Este es el test que faltaba y por el que se coló el fallo: había `Hitbox`,
## había `AttackData` y había kit, pero nadie llamaba a `enable()` en la partida
## real porque los `AnimationPlayer` estaban vacíos. Los tests de `Hitbox`
## aislada pasaban igual. Lo que se prueba aquí es **el cableado**.

const SwordKitScene := preload("res://characters/player/kits/sword_kit.tscn")

var kit: SwordKit
var attacker: Attacker
var hitbox: Hitbox


func before_each() -> void:
	kit = SwordKitScene.instantiate() as SwordKit
	add_child_autofree(kit)
	await get_tree().process_frame
	attacker = kit.get_node("Attacker") as Attacker
	hitbox = kit.get_node("Hitbox") as Hitbox


func test_el_kit_tiene_su_repertorio_de_ataques() -> void:
	assert_eq(attacker.attacks.size(), 3, "combo de tres golpes")
	for data in attacker.attacks:
		assert_not_null(data, "ningún AttackData puede quedar sin asignar")


func test_las_animaciones_de_los_ataques_existen() -> void:
	var animation_player := kit.get_node("AnimationPlayer") as AnimationPlayer
	for data in attacker.attacks:
		assert_true(animation_player.has_animation(data.animation),
				"falta la animación '%s'; sin ella el golpe no abre ventana" % data.animation)


func test_la_hitbox_arranca_apagada() -> void:
	assert_false(hitbox.is_active())


func test_atacar_abre_la_ventana_de_dano() -> void:
	attacker.attack(1)
	assert_true(attacker.is_attacking(), "el ataque arranca")

	# La animación abre la ventana en 0.10 s. Se espera y se comprueba.
	await wait_seconds(0.14)
	assert_true(hitbox.is_active(),
			"la pista de método de la animación debe haber encendido la hitbox")


func test_la_ventana_de_dano_se_cierra_sola() -> void:
	attacker.attack(1)
	await wait_seconds(0.14)
	assert_true(hitbox.is_active(), "abierta a mitad del golpe")

	await wait_seconds(0.16)
	assert_false(hitbox.is_active(), "cerrada al pasar los frames activos")


func test_el_ataque_termina_y_libera_al_atacante() -> void:
	attacker.attack(1)
	await wait_seconds(0.5)
	assert_false(attacker.is_attacking(), "sin encadenar, el atacante queda libre")
	assert_false(hitbox.is_active())


func test_la_hitbox_toma_los_valores_del_ataque_en_curso() -> void:
	# El tercer golpe pega más fuerte: la hitbox debe reconfigurarse por golpe.
	var heavy: AttackData = attacker.attacks[2]
	attacker._index = 2
	attacker.open_window()

	assert_eq(hitbox.damage, heavy.damage)
	assert_eq(hitbox.knockback, heavy.knockback)
	assert_eq(hitbox.attack_id, heavy.attack_id)
	assert_eq(hitbox.max_targets, heavy.max_targets)


func test_pulsar_durante_el_golpe_encadena_el_siguiente() -> void:
	attacker.attack(1)
	await wait_seconds(0.1)
	attacker.attack(1)   ## encadena

	await wait_seconds(0.3)
	assert_true(attacker.is_attacking(), "sigue atacando: entró el segundo golpe")
	var data := attacker.current_attack()
	assert_eq(data.animation, &"attack_2", "y es el segundo del combo")


func test_sin_encadenar_la_cadena_vuelve_al_principio() -> void:
	attacker.attack(1)
	await wait_seconds(0.5)
	attacker.attack(1)

	var data := attacker.current_attack()
	assert_eq(data.animation, &"attack_1",
			"pasada la ventana, el combo empieza de cero")


func test_un_ataque_que_no_encadena_corta_la_cadena() -> void:
	var heavy: AttackData = attacker.attacks[2]
	assert_false(heavy.chains, "el golpe fuerte cierra el combo por diseño")


func test_interrumpir_cierra_la_ventana_y_libera() -> void:
	attacker.attack(1)
	await wait_seconds(0.14)
	assert_true(hitbox.is_active())

	attacker.interrupt()
	assert_false(hitbox.is_active(), "el daño recibido corta la ventana")
	assert_false(attacker.is_attacking())


func test_el_ataque_pide_desplazamiento_sin_moverlo_el_mismo() -> void:
	watch_signals(attacker)
	attacker.attack(1)
	assert_signal_emitted(attacker, "lunge_requested",
			"el atacante pide el impulso; no escribe velocidad ajena")


func test_el_kit_queda_ocupado_mientras_ataca() -> void:
	assert_false(kit.is_busy())
	attacker.attack(1)
	await get_tree().process_frame
	assert_true(kit.is_busy(), "el kit se marca ocupado al empezar el golpe")

	await wait_seconds(0.5)
	assert_false(kit.is_busy(), "y se libera al acabar la cadena")
