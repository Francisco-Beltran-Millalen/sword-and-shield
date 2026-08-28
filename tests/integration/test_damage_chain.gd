extends GutTest

## La cadena de daño completa, de punta a punta:
##
##   atacar → animación → ventana → hitbox toca hurtbox → DamageReceiver →
##   defensa por stats → salud descontada → empuje pedido
##
## Es la prueba de que los componentes están CABLEADOS, no solo escritos. Y de
## que sirven a una entidad cualquiera: el maniquí de estos tests no es un
## `Player`, es un `CharacterBody2D` pelado con los mismos componentes. Si algo
## se acoplara al jugador, esto dejaría de compilar.

const SwordKitScene := preload("res://characters/player/kits/sword_kit.tscn")
const HurtboxScript := preload("res://components/hurtbox.gd")
const HealthScript := preload("res://components/health_component.gd")
const StatsScript := preload("res://components/stats_component.gd")
const ReceiverScript := preload("res://components/combat/damage_receiver.gd")

const LAYER_ENEMY_HURTBOX := 1 << 6

var kit: SwordKit
var attacker: Attacker
var dummy: CharacterBody2D
var dummy_health: HealthComponent
var dummy_receiver: DamageReceiver


func before_each() -> void:
	kit = SwordKitScene.instantiate() as SwordKit
	add_child_autofree(kit)
	kit.global_position = Vector2.ZERO
	await get_tree().process_frame
	attacker = kit.get_node("Attacker") as Attacker

	dummy = _build_dummy()
	add_child_autofree(dummy)
	dummy.global_position = Vector2(34, -24)   ## bajo la hitbox de la espada
	await get_tree().process_frame


## Un maniquí que NO es un Player: solo componentes. Si el combate estuviera
## acoplado al jugador, esto no funcionaría.
func _build_dummy() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "Dummy"

	var stats := StatsScript.new() as StatsComponent
	stats.name = "StatsComponent"
	body.add_child(stats)

	var health := HealthScript.new() as HealthComponent
	health.name = "HealthComponent"
	health.max_health = 10
	health.invulnerability_seconds = 0.0
	body.add_child(health)
	dummy_health = health

	var hurtbox := HurtboxScript.new() as Hurtbox
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = LAYER_ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.health_component = health
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 60)
	shape.shape = rect
	hurtbox.add_child(shape)
	body.add_child(hurtbox)

	var receiver := ReceiverScript.new() as DamageReceiver
	receiver.name = "DamageReceiver"
	receiver.hurtbox = hurtbox
	receiver.health = health
	receiver.stats = stats
	body.add_child(receiver)
	dummy_receiver = receiver

	return body


func test_un_golpe_de_espada_baja_la_salud() -> void:
	var before := dummy_health.current_health
	attacker.attack(1)
	await wait_seconds(0.25)

	assert_lt(dummy_health.current_health, before,
			"la cadena completa debe descontar salud; si no, la ventana nunca se abrió")


func test_el_dano_es_el_del_ataque_en_curso() -> void:
	var data: AttackData = attacker.attacks[0]
	var before := dummy_health.current_health

	attacker.attack(1)
	await wait_seconds(0.25)

	assert_eq(before - dummy_health.current_health, data.damage,
			"el daño aplicado es el que declara el AttackData")


func test_sin_atacar_no_hay_dano() -> void:
	var before := dummy_health.current_health
	await wait_seconds(0.3)
	assert_eq(dummy_health.current_health, before,
			"la espada apoyada encima no hiere: la hitbox está apagada")


func test_el_receptor_pide_empuje() -> void:
	watch_signals(dummy_receiver)
	attacker.attack(1)
	await wait_seconds(0.25)

	assert_signal_emitted(dummy_receiver, "knockback_requested",
			"el receptor pide el empuje; no mueve el cuerpo por su cuenta")


func test_la_defensa_escala_el_dano_recibido() -> void:
	# Duplicar la defensa duplica el daño encajado: el receptor lee los stats
	# de su propia entidad, no los del atacante.
	assert_eq(dummy_receiver.preview_damage(2), 2, "defensa 1.0 deja el daño igual")

	dummy_receiver.stats.base_defense = 2.0
	dummy_receiver.stats.mark_dirty()
	assert_eq(dummy_receiver.preview_damage(2), 4)


func test_un_solo_golpe_no_hiere_dos_veces() -> void:
	var before := dummy_health.current_health
	var data: AttackData = attacker.attacks[0]

	attacker.attack(1)
	await wait_seconds(0.4)

	assert_eq(before - dummy_health.current_health, data.damage,
			"max_targets = 1: la misma activación no repite sobre la misma víctima")


func test_el_atacante_queda_atribuido_en_el_dano() -> void:
	var registro: Array[Node] = []
	dummy_receiver.damage_taken.connect(
		func(_amount: int, from: Node, _pos: Vector2) -> void: registro.append(from))

	attacker.attack(1)
	await wait_seconds(0.25)

	assert_eq(registro.size(), 1, "un golpe, un registro")
	assert_not_null(registro[0],
			"el daño debe venir atribuido: `owner` resuelve el atacante sin exigir CharacterBody2D")


func test_una_entidad_sin_hurtbox_no_estorba() -> void:
	var mudo := CharacterBody2D.new()
	add_child_autofree(mudo)
	mudo.global_position = Vector2(34, -24)
	await get_tree().process_frame

	attacker.attack(1)
	await wait_seconds(0.25)
	pass_test("un cuerpo sin hurtbox se ignora sin romper nada")
