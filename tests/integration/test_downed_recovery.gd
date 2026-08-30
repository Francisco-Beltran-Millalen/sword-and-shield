extends GutTest

## Qué pasa DESPUÉS de caer: que el caído encaje el empuje del golpe que lo mató
## y que reaparezca quieto.
##
## Existe por un fallo medido. El empuje del golpe letal se guardaba en la cola
## `_pending_impulse` del `Player` y no se gastaba nunca, porque la rama DOWNED
## de `_physics_process` retornaba antes del único sitio que la consumía. La
## secuencia lo hacía inevitable, no raro: `HealthComponent.take_damage` emite
## `depleted` DENTRO de la llamada, así que el jugador ya está en DOWNED cuando
## `DamageReceiver` pide el empuje, once líneas después. Segundo y medio más
## tarde el `World` revivía y recolocaba, y la cola salía entera: el revivido
## aparecía a (363, -200) y derivaba 42 px.
##
## La suite daba 176/176 porque ningún test mataba a un jugador CON empuje y lo
## revivía.

const Harness := preload("res://tests/integration/_harness.gd")
const HitboxScript := preload("res://components/hitbox.gd")

const LAYER_PLAYER_HITBOX := 1 << 3
const LAYER_PLAYER_HURTBOX := 1 << 4

var h: IntegrationHarness
var victima: Player


func before_each() -> void:
	h = Harness.new()
	add_child(h)
	h.setup()
	victima = h.sword_player
	await h.tick_physics(4)   ## que asiente en el suelo


func after_each() -> void:
	h.teardown()
	await get_tree().process_frame


## Un golpe mortal con empuje, por el camino real: un `Area2D` que se enciende
## sobre la hurtbox del jugador. No se llama a `take_damage` a mano — el fallo
## vivía justo en el orden entre la muerte y la petición de empuje.
func _golpe_mortal_con_empuje() -> void:
	var hitbox := HitboxScript.new() as Hitbox
	hitbox.name = "HitboxDePrueba"
	hitbox.damage = 99
	hitbox.knockback = 400.0
	hitbox.collision_layer = LAYER_PLAYER_HITBOX
	hitbox.collision_mask = LAYER_PLAYER_HURTBOX
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 60)
	shape.shape = rect
	hitbox.add_child(shape)
	h.add_child(hitbox)
	hitbox.global_position = victima.global_position + Vector2(0.0, -22.0)
	await h.tick_physics(1)
	hitbox.enable()
	await h.tick_physics(3)


func test_el_caido_encaja_el_empuje_del_golpe_que_lo_mato() -> void:
	await _golpe_mortal_con_empuje()

	assert_true(victima.state_machine.is_in(Player.State.DOWNED),
			"el golpe tenía que matarlo")
	# La aserción que importa: un caído que NO consume su cola se queda a cero
	# aquí y guarda el empuje para la reaparición.
	assert_gt(absf(victima.velocity.x), 1.0,
			"el caído tiene que encajar el empuje en el acto, no guardárselo")


func test_el_caido_se_frena_solo() -> void:
	await _golpe_mortal_con_empuje()
	await h.tick_physics(30)

	assert_almost_eq(victima.velocity.x, 0.0, 5.0,
			"la fricción de la locomoción tiene que frenar al cadáver")


func test_reaparece_quieto_y_no_sale_disparado() -> void:
	await _golpe_mortal_con_empuje()
	await h.tick_physics(30)

	# Lo que hace `World._on_entity_downed` al vencer su temporizador.
	victima.revive_full()
	victima.place_at(Vector2(500.0, 0.0))

	# Un frame DESPUÉS de recolocar: `place_at` pone `velocity` a cero, así que
	# afirmarlo en el acto pasaría también con el fallo puesto. La cola estallaba
	# en el primer `_physics_process` posterior.
	await h.tick_physics(1)
	assert_almost_eq(victima.velocity.x, 0.0, 5.0,
			"el revivido no puede salir disparado con el empuje que lo mató")

	await h.tick_physics(20)
	assert_almost_eq(victima.global_position.x, 500.0, 8.0,
			"y no puede derivar del punto donde se le dejó")
