class_name DamageReceiver
extends Node

## Convierte un impacto en daño: escucha una `Hurtbox`, aplica la defensa de
## los stats, descuenta salud y pide el empuje.
##
## Vivía dentro de `Player._on_wounded`, donde solo servía al jugador. Como
## componente lo usan igual un enemigo, un objeto destructible o un NPC: se le
## asignan hurtbox, salud y stats, y hace el resto.
##
## No mueve a nadie: **pide** el empuje por señal y quien lo reciba decide (§2).
## Tampoco decide qué pasa al morir — eso lo hace el dueño escuchando a su
## `HealthComponent`.
##
## **Quién aplica el daño en red.** Con autoridad por jugador, la salud de cada
## personaje la escribe su propio peer y viaja de ahí hacia fuera. Un golpe
## detectado en otro peer —el host simulando un enemigo, que es el caso en
## cuanto entra el primero— descontaría salud en un lado y la replicación lo
## pisaría en el siguiente `on_change`: el enemigo solo heriría al jugador que
## hospeda. Por eso el impacto se detecta donde ocurre pero se **encamina** al
## peer que manda sobre la víctima, que es el único que lo aplica.

## Se encajó un golpe. `amount` es el daño ya aplicado.
signal damage_taken(amount: int, from: Node, hit_position: Vector2)
## Pide desplazar al dueño por el impacto.
signal knockback_requested(impulse: Vector2)
## El golpe se descartó (invulnerable, ya muerto, hurtbox inactiva).
signal hit_ignored(from: Node)

## De dónde llegan los impactos. Vacío = se busca un hermano `Hurtbox`.
@export var hurtbox: Hurtbox
## A quién se le descuenta. Vacío = se busca un hermano `HealthComponent`.
@export var health: HealthComponent
## De dónde salen defensa y resistencia al empuje. Opcional: sin stats se
## aplican daño y empuje tal cual vienen.
@export var stats: StatsComponent


func _ready() -> void:
	if hurtbox == null:
		hurtbox = _sibling("Hurtbox") as Hurtbox
	if health == null:
		health = _sibling("HealthComponent") as HealthComponent
	if stats == null:
		stats = _sibling("StatsComponent") as StatsComponent

	if hurtbox != null:
		hurtbox.wounded.connect(_on_wounded)
	else:
		push_warning("DamageReceiver sin Hurtbox: no recibirá impactos.")


## Daño que produciría este golpe, ya escalado por la defensa. Público para que
## un HUD o una IA puedan anticiparlo sin aplicarlo.
func preview_damage(raw: int) -> int:
	var defense := 1.0
	if stats != null:
		defense = stats.get_stat(StatsComponent.StatID.DEFENSE)
	return maxi(1, int(round(float(raw) * defense)))


## ¿Manda este peer sobre la entidad que recibe el golpe? Sin sesión de red
## (tests, escena suelta) manda siempre: la autoridad por defecto de un nodo es
## el peer 1 y el `OfflineMultiplayerPeer` que Godot deja puesto también.
##
## Fuera del árbol se resuelve aquí y punto: `is_multiplayer_authority()` es un
## error de motor si el nodo no está dentro (medido), y encaminar el golpe a otro
## peer tampoco sería posible. El guardia `has_multiplayer_peer()` que había en su
## lugar decía cubrir la desconexión, pero eso resultó falso al medirlo: el motor
## no retira el peer cuando cae el otro extremo.
func _owns_entity() -> bool:
	var entity := get_parent()
	if entity == null or not entity.is_inside_tree():
		return true
	return entity.is_multiplayer_authority()


func _on_wounded(hitbox: Hitbox, hit_position: Vector2) -> void:
	var entity := get_parent() as Node2D
	var direction := Vector2.ZERO
	if entity != null:
		direction = hitbox.direction_to(entity)

	if _owns_entity():
		_resolve(hitbox.damage, hitbox.knockback, direction, hit_position, hitbox.attacker())
		return

	# El golpe lo vio este peer, pero la salud de la víctima la lleva otro. Se
	# le encamina el impacto ya resuelto en geometría; el atacante no viaja
	# porque un `Node` no es serializable, y en el otro extremo el crédito se
	# atribuye a la sesión, no a una instancia concreta.
	#
	# Se comprueba que el dueño siga en la sesión: `rpc_id` a un peer que ya no
	# está es un error de motor ("Attempt to call RPC with unknown peer ID"). Pasa
	# en la ventana entre que alguien se desconecta y su personaje sale del árbol,
	# y sin sesión de red pasaría con cualquier entidad de autoridad ajena, porque
	# `get_peers()` viene vacío. Un golpe que no se puede encaminar se descarta:
	# quien manda sobre esa víctima ya no está para aplicarlo.
	var owner_peer := entity.get_multiplayer_authority()
	if not multiplayer.get_peers().has(owner_peer):
		return
	_receive_routed_hit.rpc_id(owner_peer,
			hitbox.damage, hitbox.knockback, direction, hit_position)


## Golpe encaminado desde el peer que lo detectó. `any_peer` porque quien lo
## envía no es la autoridad de esta entidad — precisamente por eso lo envía. En
## un cooperativo contra el entorno confiar en el otro cliente es aceptable; si
## algún día hay competitivo, aquí es donde entra la validación.
@rpc("any_peer", "call_remote", "reliable")
func _receive_routed_hit(raw_damage: int, knockback: float,
		direction: Vector2, hit_position: Vector2) -> void:
	if not _owns_entity():
		return
	_resolve(raw_damage, knockback, direction, hit_position, null)


func _resolve(raw_damage: int, knockback: float, direction: Vector2,
		hit_position: Vector2, source: Node) -> void:
	if health == null:
		hit_ignored.emit(source)
		return
	if health.is_dead or health.is_invulnerable():
		hit_ignored.emit(source)
		return

	var amount := preview_damage(raw_damage)
	var applied := health.take_damage(amount, source)
	if applied <= 0:
		hit_ignored.emit(source)
		return

	damage_taken.emit(applied, source, hit_position)

	var resistance := 1.0
	if stats != null:
		resistance = stats.get_stat(StatsComponent.StatID.KNOCKBACK_TAKEN)
	if knockback > 0.0:
		knockback_requested.emit(direction * knockback * resistance)


func _sibling(node_name: String) -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null(node_name)
