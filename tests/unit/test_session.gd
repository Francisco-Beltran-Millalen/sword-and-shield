extends GutTest

## Reparto de kits. Lo importante que se prueba aquí: el reparto es
## determinista por `peer_id`, así que cada cliente lo calcula solo y no puede
## desincronizarse del host.

const SessionScript := preload("res://systems/network/session.gd")

var session: Session


func before_each() -> void:
	session = SessionScript.new()
	add_child_autofree(session)


func test_el_host_lleva_espada() -> void:
	assert_eq(session.kit_for(Session.HOST_PEER), Session.Kit.SWORD)


func test_quien_se_une_lleva_escudo() -> void:
	assert_eq(session.kit_for(2837465), Session.Kit.SHIELD,
			"cualquier peer que no sea el host lleva escudo")


func test_el_reparto_es_deterministico_sin_acordar_nada() -> void:
	# Dos instancias distintas —simulando dos clientes que nunca se hablaron—
	# deben llegar al mismo reparto solo a partir del peer_id.
	var other := SessionScript.new()
	add_child_autofree(other)

	for peer in [1, 2, 77, 1234567]:
		assert_eq(session.kit_for(peer), other.kit_for(peer),
				"peer %d debe recibir el mismo kit en ambos clientes" % peer)


func test_cada_kit_resuelve_a_una_escena_distinta() -> void:
	var sword := session.kit_scene_for(Session.HOST_PEER)
	var shield := session.kit_scene_for(2)

	assert_not_null(sword, "la espada debe resolver a una escena cargable")
	assert_not_null(shield, "el escudo debe resolver a una escena cargable")
	assert_ne(sword.resource_path, shield.resource_path)


func test_el_reparto_explicito_gana_al_deterministico() -> void:
	session.assign(1, 2)
	assert_eq(session.kit_for(1), Session.Kit.SWORD)
	assert_eq(session.kit_for(2), Session.Kit.SHIELD)

	# Invertido a mano: es lo que permitirá elegir kit en el lobby.
	session.kit_by_peer = {1: Session.Kit.SHIELD, 2: Session.Kit.SWORD}
	assert_eq(session.kit_for(1), Session.Kit.SHIELD)
	assert_eq(session.kit_for(2), Session.Kit.SWORD)


func test_clear_vuelve_al_reparto_deterministico() -> void:
	session.kit_by_peer = {1: Session.Kit.SHIELD}
	assert_eq(session.kit_for(1), Session.Kit.SHIELD)

	session.clear()
	assert_eq(session.kit_for(1), Session.Kit.SWORD,
			"tras clear() manda de nuevo la regla determinista")


func test_los_nombres_de_kit_son_legibles() -> void:
	assert_eq(session.kit_name_for(1), "Espada")
	assert_eq(session.kit_name_for(2), "Escudo")
