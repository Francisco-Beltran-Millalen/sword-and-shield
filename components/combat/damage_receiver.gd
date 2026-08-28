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


func _on_wounded(hitbox: Hitbox, hit_position: Vector2) -> void:
	var source := hitbox.attacker()

	if health == null:
		hit_ignored.emit(source)
		return
	if health.is_dead or health.is_invulnerable():
		hit_ignored.emit(source)
		return

	var amount := preview_damage(hitbox.damage)
	var applied := health.take_damage(amount, source)
	if applied <= 0:
		hit_ignored.emit(source)
		return

	damage_taken.emit(applied, source, hit_position)

	var resistance := 1.0
	if stats != null:
		resistance = stats.get_stat(StatsComponent.StatID.KNOCKBACK_TAKEN)
	var owner_node := get_parent() as Node2D
	if owner_node != null and hitbox.knockback > 0.0:
		knockback_requested.emit(hitbox.direction_to(owner_node) * hitbox.knockback * resistance)


func _sibling(node_name: String) -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null(node_name)
