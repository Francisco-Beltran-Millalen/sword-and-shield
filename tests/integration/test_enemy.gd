extends GutTest

## El enemigo, de punta a punta.
##
## Lo que de verdad se prueba aquí no es el enemigo: es que los componentes
## sirven a una entidad que no es el jugador. El enemigo no estrena movimiento
## ni combate —usa `Locomotion`, `Attacker`, `Hitbox`, `Hurtbox`,
## `DamageReceiver` y `AttackData` tal cual—, así que si algo de eso estuviera
## acoplado al `Player`, estos tests serían los que lo destaparían.

const Harness := preload("res://tests/integration/_harness.gd")
const EnemyScene := preload("res://characters/enemy/enemy.tscn")
const ScriptedSource := preload("res://tests/integration/scripted_intent_source.gd")

var h: IntegrationHarness
var enemy: Enemy


func before_each() -> void:
	h = Harness.new()
	add_child(h)
	h.setup()


func after_each() -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()
	h.teardown()
	# `queue_free()` no libera hasta el final del frame, y GUT cuenta los hijos
	# del script en cuanto vuelve de aquí: sin esperar, avisa de nodos sin
	# liberar que sí se van a liberar. Ese aviso tapa los de verdad.
	await get_tree().process_frame


## Coloca un enemigo. `scripted` sustituye su IA por un guion de test, que es la
## prueba de que la IA es intercambiable por nodo igual que la del jugador.
##
## `archetype` se asigna ANTES de entrar en el árbol a propósito: quien reparte
## sus números entre los componentes es `_apply_archetype`, y corre en `_ready`.
func _spawn_enemy(at: Vector2, scripted: bool = false,
		archetype: EnemyArchetype = null) -> Enemy:
	var instance := EnemyScene.instantiate() as Enemy
	if archetype != null:
		instance.archetype = archetype
	if scripted:
		var original := instance.get_node("IntentSource")
		original.name = "IntentSourceRetired"
		instance.remove_child(original)
		original.queue_free()
		var guion := ScriptedSource.new()
		guion.name = "IntentSource"
		instance.add_child(guion)
		guion.owner = instance
	h.add_child(instance)
	instance.global_position = at
	return instance


func test_el_enemigo_se_monta_con_los_componentes_del_jugador() -> void:
	enemy = _spawn_enemy(Vector2(300.0, 0.0))
	await h.tick_physics(2)

	assert_not_null(enemy.get_script(), "sin script el nodo se instancia igual y no hace nada")
	for pieza: String in ["StatsComponent", "HealthComponent", "StateMachine",
			"Locomotion", "DamageReceiver", "Attacker", "Hurtbox", "Perception"]:
		assert_not_null(enemy.get_node_or_null(pieza),
				"el enemigo reutiliza '%s'; si le hiciera falta uno propio, es que estaba acoplado al jugador" % pieza)


func test_el_arquetipo_manda_sobre_los_componentes() -> void:
	enemy = _spawn_enemy(Vector2(300.0, 0.0))
	await h.tick_physics(2)

	assert_eq(enemy.health.max_health, enemy.archetype.max_health,
			"la salud sale del .tres, no del inspector de la escena")
	assert_almost_eq(enemy.stats.get_stat(StatsComponent.StatID.MAX_SPEED),
			enemy.archetype.move_speed, 0.01,
			"la velocidad también: un enemigo nuevo es un .tres, no un script")


func test_la_espada_del_jugador_hiere_al_enemigo() -> void:
	await h.settle_on_floor()
	var jugador := h.sword_player
	enemy = _spawn_enemy(jugador.global_position + Vector2(34.0, 0.0))
	await h.tick_physics(2)

	var antes := enemy.health.current_health
	h.sword_input.set_move(1.0)
	await h.tick_physics(2)
	h.sword_input.press_attack()
	await h.tick_physics(20)

	assert_lt(enemy.health.current_health, antes,
			"la hitbox de la espada (máscara 192) alcanza la hurtbox del enemigo (capa 64)")


func test_el_golpe_del_enemigo_hiere_al_jugador() -> void:
	await h.settle_on_floor()
	var jugador := h.sword_player
	enemy = _spawn_enemy(jugador.global_position + Vector2(40.0, 0.0), true)
	await h.tick_physics(2)

	var guion := enemy.get_node("IntentSource") as ScriptedIntentSource
	var antes := jugador.health.current_health
	guion.set_move(-1.0)   ## mirar al jugador
	await h.tick_physics(2)
	guion.press_attack()
	await h.tick_physics(45)

	assert_lt(jugador.health.current_health, antes,
			"la hitbox del enemigo (máscara 144) alcanza la hurtbox del jugador (capa 16)")


func test_el_escudo_bloquea_el_golpe_del_enemigo() -> void:
	await h.settle_on_floor()
	var escudo := h.shield_player
	# A 70 px: el golpe llega al escudo por delante. Más cerca, la hitbox lo
	# atraviesa y queda a su espalda, donde `GuardBox.covers()` la descarta con
	# razón — un escudo frontal no protege por detrás.
	enemy = _spawn_enemy(escudo.global_position + Vector2(70.0, 0.0), true)
	await h.tick_physics(2)

	# Guardia arriba y mirando al enemigo.
	h.shield_input.set_move(1.0)
	await h.tick_physics(3)
	h.shield_input.set_move(0.0)
	h.shield_input.set_guard(true)
	await h.tick_physics(3)

	var guard_box: GuardBox = escudo.kit.get_node("GuardBox")
	assert_true(guard_box.is_raised(), "la guardia está levantada antes del golpe")

	watch_signals(guard_box)
	var guion := enemy.get_node("IntentSource") as ScriptedIntentSource
	guion.set_move(-1.0)
	await h.tick_physics(2)
	guion.set_move(0.0)   ## ya encara al escudo; que no siga avanzando
	guion.press_attack()
	await h.tick_physics(45)

	assert_signal_emitted(guard_box, "blocked",
			"el escudo intercepta el golpe del enemigo igual que el de otro jugador")


func test_el_enemigo_va_hacia_quien_ve() -> void:
	await h.settle_on_floor()
	var jugador := h.sword_player
	enemy = _spawn_enemy(jugador.global_position + Vector2(200.0, 0.0))
	await h.tick_physics(2)

	var distancia_inicial := absf(enemy.global_position.x - jugador.global_position.x)
	await h.tick_physics(40)
	var distancia_final := absf(enemy.global_position.x - jugador.global_position.x)

	assert_lt(distancia_final, distancia_inicial,
			"con el jugador dentro del radio de visión, el enemigo se acerca")


func test_sin_nadie_a_la_vista_ronda_su_sitio() -> void:
	var origen := Vector2(600.0, 0.0)   ## sobre el suelo, fuera del radio de visión
	enemy = _spawn_enemy(origen)
	await h.tick_physics(40)

	assert_false(enemy.perception.has_targets(), "no ve a nadie desde ahí")
	assert_lt(absf(enemy.global_position.x - origen.x),
			enemy.archetype.patrol_radius + 60.0,
			"la ronda se queda alrededor de donde apareció")


func test_al_morir_queda_derrotado_y_no_se_libera() -> void:
	enemy = _spawn_enemy(Vector2(300.0, 0.0))
	await h.tick_physics(2)

	enemy.health.kill()
	await h.tick_physics(2)

	assert_true(is_instance_valid(enemy),
			"no se libera: `queue_free()` en el host no viaja a los clientes, " +
			"y el enemigo vive dentro de la escena de su zona")
	assert_eq(enemy.state_machine.current_state, Enemy.State.DOWNED,
			"queda derrotado, y ese estado sí se replica")
	assert_false(enemy.hurtbox.active, "un enemigo derrotado ya no encaja golpes")


## --- Que dos enemigos no se pisen el cuerpo ---

## Un arquetipo de test. Se construye en memoria y no como `.tres`: un recurso
## nuevo en el repo sería contenido especulativo, y aquí solo hace falta que sus
## medidas NO coincidan con las del recluta.
func _archetype_de_prueba(body: Vector2, vista: float) -> EnemyArchetype:
	var archetype := EnemyArchetype.new()
	archetype.display_name = "Prueba"
	archetype.body_size = body
	archetype.max_health = 6
	archetype.detection_range = vista
	archetype.leash_range = vista * 1.5
	archetype.attacks = []
	return archetype


func test_dos_enemigos_distintos_no_se_pisan_el_cuerpo() -> void:
	# El recluta de la escena, tal cual: 44x44 y 260 de vista.
	enemy = _spawn_enemy(Vector2(300.0, 0.0))
	var grande := _spawn_enemy(Vector2(700.0, 0.0), false,
			_archetype_de_prueba(Vector2(120.0, 120.0), 900.0))
	await h.tick_physics(2)

	# Se lee LA FORMA, no el arquetipo: el arquetipo siempre dice la verdad, y
	# lo que se pisaba era el `RectangleShape2D` que ambas instancias
	# compartían. Sin `resource_local_to_scene`, el último en montarse le
	# imponía su cuerpo, su hurtbox y su vista al primero.
	var cuerpo := (enemy.body_shape.shape as RectangleShape2D).size
	assert_eq(cuerpo, Vector2(44.0, 44.0),
			"el recluta conserva su cuerpo aunque monte otro enemigo mayor")

	var hurt_shape := enemy.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	assert_eq((hurt_shape.shape as RectangleShape2D).size, Vector2(44.0, 44.0),
			"y su hurtbox, o encajaría golpes que no le tocan")

	var ojos := enemy.perception.get_node("CollisionShape2D") as CollisionShape2D
	assert_almost_eq((ojos.shape as CircleShape2D).radius, 260.0, 0.1,
			"y su radio de visión")

	# Y el grande sigue siendo grande: la separación va en los dos sentidos.
	assert_eq((grande.body_shape.shape as RectangleShape2D).size, Vector2(120.0, 120.0),
			"el segundo enemigo conserva el suyo")

	grande.queue_free()


func test_el_enemigo_estrena_el_rig_compartido() -> void:
	# Fase 4. El cuerpo ya no es un rectángulo: es el rig de `body_rig.tscn`, y la
	# escala y el color de rol salen de `_apply_body_size` (modulate + scale), no
	# de polígonos duplicados. Dos enemigos con arquetipos distintos no se pisan.
	enemy = _spawn_enemy(Vector2(300.0, 0.0))
	var arquetipo_grande := _archetype_de_prueba(Vector2(120.0, 120.0), 900.0)
	arquetipo_grande.body_color = Color(0.2, 0.5, 0.9, 1.0)
	var grande := _spawn_enemy(Vector2(700.0, 0.0), false, arquetipo_grande)
	await h.tick_physics(2)

	var rig := enemy.get_node("Visuals/Skeleton") as Node2D
	assert_not_null(rig, "el enemigo estrena el rig compartido")
	assert_true(rig.get_node("Hip") is Bone2D, "el rig trae sus huesos")
	assert_eq(rig.scale, Vector2.ONE, "el recluta de 44 px no escala el rig")
	assert_almost_eq(rig.modulate.r, enemy.archetype.body_color.r, 0.01,
			"el color de rol sale por modulate")

	var rig_grande := grande.get_node("Visuals/Skeleton") as Node2D
	assert_almost_eq(rig_grande.scale.y, 120.0 / 44.0, 0.01,
			"el enemigo de 120 px escala el rig (quedó en %.2f)" % rig_grande.scale.y)
	assert_almost_eq(rig_grande.modulate.b, 0.9, 0.01,
			"y el segundo enemigo no le impone su color al primero")

	grande.queue_free()
