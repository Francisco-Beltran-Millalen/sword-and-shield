class_name Session
extends Node

## Reparto de la partida: qué peer lleva espada y qué peer lleva escudo.
##
## El host decide y lo comunica; no se negocia. Es un autoload ligero de sesión
## en el sentido de §9: su estado vive lo que vive la partida y `clear()` lo
## deja como al arrancar.
##
## Con kits fijos, el arma NO se replica cada frame — se acuerda una vez al
## conectar. Ese es el ahorro de tratar el kit como decisión de sesión y no
## como estado de personaje.

enum Kit { SWORD, SHIELD }

const KIT_SCENES: Dictionary = {
	Kit.SWORD: "res://characters/player/kits/sword_kit.tscn",
	Kit.SHIELD: "res://characters/player/kits/shield_kit.tscn",
}

## Peer del host en ENet. Siempre 1.
const HOST_PEER: int = 1

## peer_id -> Kit. Vacío = reparto determinista (ver `kit_for`).
var kit_by_peer: Dictionary = {}


## Reparto explícito, para cuando el lobby permita elegir. Mientras esté vacío
## manda la regla determinista.
func assign(host_peer: int, guest_peer: int) -> void:
	kit_by_peer = {
		host_peer: Kit.SWORD,
		guest_peer: Kit.SHIELD,
	}


## Quien hospeda lleva espada; quien se une, escudo.
##
## La regla es determinista a propósito: cada peer la calcula por su cuenta a
## partir del `peer_id`, así que el reparto no necesita replicarse ni acordarse
## por RPC. Un desajuste de kits entre cliente y host es imposible por
## construcción, no por sincronización correcta.
func kit_for(peer_id: int) -> Kit:
	if not kit_by_peer.is_empty():
		return kit_by_peer.get(peer_id, Kit.SWORD)
	return Kit.SWORD if peer_id == HOST_PEER else Kit.SHIELD


func kit_scene_for(peer_id: int) -> PackedScene:
	var path: String = KIT_SCENES[kit_for(peer_id)]
	return load(path) as PackedScene


func kit_name_for(peer_id: int) -> String:
	return "Espada" if kit_for(peer_id) == Kit.SWORD else "Escudo"


func clear() -> void:
	kit_by_peer.clear()
