extends GutTest

## El HUD, probado por donde falla de verdad: el arranque.
##
## Una barra de salud es trivial de dejar "en verde" y rota. El caso que este
## archivo persigue es el del valor INICIAL: `HealthComponent` emite su
## `health_changed` dentro de su `_ready`, y el `_ready` de un hijo corre antes
## que el del padre, así que quien se suscriba desde el `Player` llega tarde y no
## lo ve nunca. Un test que solo comprobara "recibe daño y la barra baja" pasaría
## con la barra a cero toda la partida.
##
## Por eso se monta el `World` entero —zona, spawner y jugadores reales— en vez
## de llamar a la API del HUD y darla por buena.

const WorldScene := preload("res://systems/world/world.tscn")
const VerdantScene := preload("res://level/zones/zone_verdant.tscn")

var world: Node2D
var hud: Hud


func before_each() -> void:
	world = WorldScene.instantiate() as Node2D
	add_child_autofree(world)
	hud = world.get_node("Hud") as Hud
	await wait_physics_frames(2)


func _bar(slot: int) -> ProgressBar:
	var nombre := "SelfHealth" if slot == Hud.Slot.SELF else "PartnerHealth"
	return hud.find_child(nombre, true, false) as ProgressBar


func _fila(slot: int) -> Control:
	var nombre := "SelfRow" if slot == Hud.Slot.SELF else "PartnerRow"
	return hud.find_child(nombre, true, false) as Control


func _aviso() -> Label:
	return hud.find_child("DoorNotice", true, false) as Label


func _primer_jugador() -> Player:
	for child in world.get_node("Players").get_children():
		var player := child as Player
		if player != null:
			return player
	return null


func test_el_mundo_hace_aparecer_al_menos_un_jugador() -> void:
	# Si esto falla, los demás tests de este archivo no prueban nada: estarían
	# midiendo un HUD que nadie alimenta.
	assert_not_null(_primer_jugador(), "el spawner del World debe crear un jugador")


func test_la_barra_arranca_llena_y_no_espera_al_primer_golpe() -> void:
	var jugador := _primer_jugador()
	assert_not_null(jugador)
	var barra := _bar(Hud.Slot.SELF)
	assert_not_null(barra, "la ranura propia debe tener barra")
	assert_gt(barra.max_value, 0.0, "la barra debe conocer el máximo desde el arranque")
	assert_eq(barra.value, barra.max_value,
			"la barra arranca llena: si vale 0 es que se perdió la emisión inicial del HealthComponent")
	assert_eq(int(barra.max_value), jugador.health.max_health,
			"el máximo de la barra es el del jugador real, no el del .tscn por defecto")


func test_la_ranura_propia_se_ve_desde_el_arranque() -> void:
	assert_true(_fila(Hud.Slot.SELF).visible, "con un jugador dentro, su ranura se muestra")


func test_la_barra_baja_cuando_el_jugador_encaja_dano() -> void:
	var jugador := _primer_jugador()
	var barra := _bar(Hud.Slot.SELF)
	var antes := barra.value
	jugador.health.take_damage(2, null)
	await wait_physics_frames(1)
	assert_eq(barra.value, antes - 2.0, "la barra sigue al HealthComponent")


func test_la_ranura_desaparece_cuando_su_jugador_se_va() -> void:
	var jugador := _primer_jugador()
	assert_true(_fila(Hud.Slot.SELF).visible)
	jugador.get_parent().remove_child(jugador)
	jugador.queue_free()
	await wait_physics_frames(2)
	assert_false(_fila(Hud.Slot.SELF).visible,
			"sin jugador la barra se retira; si no, se queda clavada en el último valor")


func test_el_aviso_de_puerta_solo_sale_mientras_falta_gente() -> void:
	var aviso := _aviso()
	hud.set_door_wait(1, 2)
	assert_true(aviso.visible, "falta un jugador: hay que decir por qué no se abre")
	assert_string_contains(aviso.text, "1/2")

	hud.set_door_wait(2, 2)
	assert_false(aviso.visible, "con los dos presentes la puerta se abre y el aviso sobra")

	hud.set_door_wait(0, 2)
	assert_false(aviso.visible, "nadie en la puerta: no hay nada que esperar")


func test_el_aviso_no_sobrevive_a_la_zona_que_lo_pidio() -> void:
	# El caso real: la puerta emite su último `waiting_changed` al salir del
	# árbol, cuando el HUD ya está enseñando la zona nueva.
	hud.set_door_wait(1, 2)
	assert_true(_aviso().visible)

	world._load_zone("res://level/zones/zone_cinder.tscn", &"")
	await wait_physics_frames(2)
	assert_false(_aviso().visible,
			"al cambiar de zona el aviso se apaga: su puerta ya no existe")


func test_la_puerta_de_la_zona_alimenta_el_aviso() -> void:
	# Que el cableado exista de verdad, no solo la API del HUD.
	var zone := world.current_zone as Zone
	var doors := zone.doors()
	assert_gt(doors.size(), 0, "la zona de arranque tiene puertas")
	assert_true(doors[0].waiting_changed.is_connected(hud.set_door_wait),
			"el World conecta cada puerta de la zona al HUD")
