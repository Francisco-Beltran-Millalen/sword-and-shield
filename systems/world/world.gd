extends Node2D

## Coordinador del mundo: sostiene la zona activa y hace aparecer a los
## jugadores.
##
## Solo hay **una** zona cargada a la vez, para los dos jugadores. Cruzar de
## zona exige que ambos estén en la puerta (`ZoneDoor.required_players`), así
## que el caso "cada jugador en una zona distinta" no existe.
## Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`.
##
## El cambio de zona lo decide el host y lo replica por RPC: es un evento raro
## y discreto, justo lo que el ADR buscaba al elegir la zona como unidad.

const PlayerScene := preload("res://characters/player/player.tscn")
const LOBBY_SCENE := "res://systems/network/lobby.tscn"
const FIRST_ZONE := "res://level/zones/zone_verdant.tscn"

@onready var players_root: Node2D = $Players
@onready var zone_root: Node2D = $ZoneRoot
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var hud: Hud = $Hud

var current_zone: Zone
var _changing_zone: bool = false


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	NetworkManager.session_ended.connect(_on_session_ended)

	_load_zone(FIRST_ZONE, &"")

	# Nadie aparece hasta que el otro extremo también tenga su árbol montado. El
	# `MultiplayerSpawner` emite una sola vez y no reintenta: si el cliente aún
	# no tiene `World/PlayerSpawner`, ese jugador no llega nunca y el cliente
	# juega —o mira— una partida sin personajes.
	#
	# ONE_SHOT porque `all_peers_ready` se emite en CADA carga acusada, no solo
	# en la primera: sin esto, el primer cambio de zona volvería a hacer aparecer
	# a los dos jugadores encima de los que ya hay.
	NetworkManager.all_peers_ready.connect(_on_everyone_loaded, CONNECT_ONE_SHOT)
	NetworkManager.report_scene_ready()


## Los jugadores los hace aparecer el host: el `MultiplayerSpawner` replica el
## resultado. Sin sesión de red el peer offline ES el servidor, así que la misma
## comprobación vale para los tres casos y no hace falta preguntar si hay red.
func _on_everyone_loaded() -> void:
	if multiplayer.is_server():
		_spawn_all()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	# Sin sesión —esta escena abierta a pelo, que el repo apoya— `leave()` hace
	# `return` y no emite `session_ended`: sin esto, Esc no hacía absolutamente
	# nada y no había forma de salir de aquí.
	if not NetworkManager.is_active:
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
	NetworkManager.leave()


## Carga una zona y descarga la anterior. La zona es la unidad de carga: dentro
## de ella no se vuelve a cargar nada.
func _load_zone(zone_path: String, from_door: StringName) -> void:
	# El aviso de puerta no puede sobrevivir a la puerta que lo pidió: un `Area2D`
	# que sale del árbol suelta sus `body_exited`, así que la puerta moribunda
	# emitiría un último `waiting_changed` que llegaría ya en la zona nueva, donde
	# no hay nada que lo apague. Se corta la conexión antes de destruirla.
	if current_zone != null:
		for door in current_zone.doors():
			door.waiting_changed.disconnect(hud.set_door_wait)
	hud.set_door_wait(0, 0)

	# Se instancia ANTES de destruir la anterior: si la carga falla a media
	# función, `current_zone` se quedaba apuntando a un nodo ya liberado y la
	# siguiente llamada le pedía sus puertas.
	var packed := load(zone_path) as PackedScene
	if packed == null:
		push_error("No se pudo cargar la zona '%s'." % zone_path)
		return

	var loaded := packed.instantiate() as Zone
	if loaded == null:
		push_error("La escena '%s' no tiene raíz Zone." % zone_path)
		return

	for child in zone_root.get_children():
		zone_root.remove_child(child)
		child.queue_free()

	current_zone = loaded
	zone_root.add_child(current_zone)

	for door in current_zone.doors():
		door.traversal_requested.connect(_on_traversal_requested)
		door.waiting_changed.connect(hud.set_door_wait)

	GameEvents.zone_entered.emit(current_zone.zone_id)

	# La puerta por la que se llega tiene que saber que los recibió, o los verá
	# entrar y pedirá volver por donde se vino. Se avisa ANTES de colocarlos.
	var entry := current_zone.door(from_door)
	if entry != null:
		entry.receive_arrival()

	_place_players(current_zone.arrival_point(from_door))


## Coloca a los viajeros de ESTE peer en el punto de llegada.
##
## Cada uno coloca el suyo (§3, autoridad por jugador) y el resultado viaja por
## el `MultiplayerSynchronizer`. Mover aquí a un cuerpo ajeno no solo escribe un
## dato de otro: su dueño lo devuelve en el paquete siguiente —`position` se
## replica en modo ALWAYS—, y ese vaivén de salir y volver a entrar es lo que la
## puerta de llegada lee como un cruce.
func _place_players(at: Vector2) -> void:
	var offset := -40.0
	for child in players_root.get_children():
		# Por método y no por tipo: cualquier cosa reubicable vale, igual que en
		# `_on_entity_downed`.
		if not child.has_method("place_at"):
			continue
		if not child.is_multiplayer_authority():
			offset += 80.0
			continue
		child.place_at(at + Vector2(offset, -40.0))
		offset += 80.0


func _on_traversal_requested(target_zone: String, target_door: StringName) -> void:
	if _changing_zone or target_zone.is_empty():
		return
	# El host decide y lo replica: el cambio de zona debe ocurrir a la vez en
	# ambos extremos o los jugadores acabarían en mundos distintos. Sin sesión de
	# red el peer offline es el servidor, así que decide igual, y el `rpc` con
	# `call_local` se entrega localmente (medido) — no hace falta bifurcar.
	if not multiplayer.is_server():
		return
	_changing_zone = true
	rpc_change_zone.rpc(target_zone, target_door)


@rpc("authority", "call_local", "reliable")
func rpc_change_zone(zone_path: String, from_door: StringName) -> void:
	# DIFERIDO SIEMPRE, y no por cortesía con la red: la petición nace en el
	# `body_entered` de una puerta, o sea DENTRO del flush de queries de física, y
	# cargar una zona añade y quita `CollisionObject2D`. Godot lo prohíbe —
	# "Removing a CollisionObject node during a physics callback is not allowed",
	# y detrás van ~1.800 "Can't change this state while flushing queries".
	#
	# Aquí había un `await process_frame` que decía ser cortesía para el cliente y
	# de hecho era lo único que sacaba la carga del callback; condicionarlo a que
	# hubiera red —que es lo que parecía decir— dejaba el camino sin proteger y
	# tumbaba los cinco tests de cruce. La razón real queda escrita, y de paso
	# vale también para quien pida el viaje desde fuera de la física.
	_perform_zone_change.call_deferred(zone_path, from_door)


func _perform_zone_change(zone_path: String, from_door: StringName) -> void:
	if NetworkManager.is_active and multiplayer.is_server():
		# Ahora sí, la cortesía: un frame para que el cliente vaya por delante. NO
		# es una garantía: con latencia mayor que un frame el host carga primero y
		# sus sincronizadores de enemigos apuntan a rutas que el cliente todavía no
		# tiene. Medido, eso son unas pocas líneas de "Node not found" y se recupera
		# solo al paquete siguiente —la posición se replica en modo ALWAYS y los
		# enemigos no los crea ningún spawner, así que no hay ningún comando de una
		# sola vez que perder—. El acuse de carga existe (ver
		# `NetworkManager.report_scene_ready`) y aquí NO se usa a propósito:
		# bloquear cada cambio de zona para ahorrar ese ruido salía más caro que el
		# ruido. Ver el mapa, tabla `Deferred`.
		await get_tree().process_frame
	_load_zone(zone_path, from_door)
	# Un solo sitio suelta el pestillo, pase lo que pase en la carga: `_load_zone`
	# tiene salidas tempranas y dejarlo puesto congelaría los viajes para siempre.
	_changing_zone = false


func _spawn_all() -> void:
	# El 1 es el host, que nunca está en `get_peers()`. Sin sesión de red la lista
	# viene vacía y queda él solo, que es el único jugador que hay.
	var peers: Array[int] = [1]
	for peer in multiplayer.get_peers():
		peers.append(peer)

	for index in range(peers.size()):
		spawner.spawn({"peer": peers[index], "index": index})


## ¿Es este el peer que manda sobre ese personaje? Se pregunta desde el `World`,
## que sí está en el árbol: `Node.multiplayer` vale `null` fuera de él, así que
## el mismo cálculo hecho sobre un jugador recién instanciado reventaría.
func _is_own_peer(peer_id: int) -> bool:
	return peer_id == multiplayer.get_unique_id()


## La ejecuta el spawner en TODOS los peers con los datos que envió el host.
func _spawn_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info.get("peer", 1)
	var index: int = info.get("index", 0)

	var player := PlayerScene.instantiate() as Player
	player.name = "Player_%d" % peer_id
	player.player_index = index
	player.display_name = SessionState.kit_name_for(peer_id)
	player.set_owning_peer(peer_id)
	player.equip_kit(SessionState.kit_scene_for(peer_id))

	# El World creó a este jugador, así que se conecta a él directamente en vez
	# de escuchar un evento global y luego buscarlo por índice. El autoload es
	# para emisores y receptores que NO pueden conocerse por el árbol; aquí sí
	# se conocen. `bind` lleva la referencia, sin búsquedas.
	# Se toma el hijo, no `player.health`: ese accesor es `@onready` y el spawner
	# ejecuta esta función ANTES de que el nodo entre en el árbol, así que
	# todavía valdría `null`. Los hijos de la escena instanciada sí existen ya.
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.depleted.connect(_on_entity_downed.bind(player))

	# Qué ranura del HUD ocupa este jugador. Se decide aquí y no en el HUD porque
	# el peer que manda sobre el personaje es un dato de la sesión, no de la
	# interfaz: el HUD recibe un entero y no pregunta nada a nadie (§5).
	var slot := Hud.Slot.SELF if _is_own_peer(peer_id) else Hud.Slot.PARTNER
	hud.set_slot_label(player.display_name, slot)
	if health != null:
		# Al `HealthComponent` y no al `Player`, que reemite la misma señal: el
		# `Player` la conecta en su `_ready`, y el `_ready` de un hijo corre ANTES
		# que el del padre, así que la emisión inicial del componente ya ha pasado
		# cuando el `Player` se suscribe. Enganchado ahí, el HUD se quedaría a cero
		# hasta el primer golpe y luego pegaría un salto. Aquí seguimos fuera del
		# árbol —nadie ha hecho `_ready` todavía—, así que no se pierde ninguna.
		health.health_changed.connect(hud.set_health.bind(slot))
	# Un jugador que se desconecta se lleva su ranura: el `MultiplayerSpawner`
	# despacha al personaje remoto y su barra se quedaría clavada en el último
	# valor que llegó a verse.
	player.tree_exiting.connect(hud.clear_slot.bind(slot))

	if current_zone != null:
		player.position = current_zone.arrival_point() + Vector2(index * 80 - 40, -40)
	return player


## Provisional: reaparecer en la sala por defecto de la zona. El sistema de
## puntos de guardado llega con la progresión.
##
## `current_zone` se lee DESPUÉS de la espera, así que si mientras tanto se cruzó
## una puerta el caído reaparece en la zona nueva. Es lo que se quiere —la zona
## vieja ya no está cargada para nadie—, pero conviene saberlo antes de tocarlo.
##
## Recibe la entidad por `bind`, así que sirve igual para un enemigo que deba
## reaparecer: no comprueba tipos ni busca por índice.
func _on_entity_downed(_source: Node, entity: Node) -> void:
	# Solo la corre el peer que manda sobre el caído. `_spawn_player` se ejecuta
	# en todos, y `HealthComponent` reemite `depleted` al llegar la salud
	# replicada, así que sin esto había dos temporizadores desfasados por la
	# latencia reviviendo y recolocando un cuerpo ajeno (§4: un solo escritor).
	if not entity.is_multiplayer_authority():
		return
	var timer := get_tree().create_timer(1.5)
	await timer.timeout
	if not is_instance_valid(entity):
		return
	if entity.has_method("revive_full"):
		entity.revive_full()
	if current_zone != null and entity.has_method("place_at"):
		entity.place_at(current_zone.arrival_point())


func _on_session_ended(_reason: String) -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
