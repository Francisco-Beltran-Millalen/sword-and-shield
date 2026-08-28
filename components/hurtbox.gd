class_name Hurtbox
extends Area2D

## Volumen que RECIBE daño. Vive siempre encendido y delega en el
## `HealthComponent` de su dueño, que ya gestiona i-frames y muerte.
##
## Configuración en el editor:
##   - `collision_layer` → la capa propia (`player_hurtbox` o `enemy_hurtbox`)
##   - `collision_mask`  → 0: la hurtbox no busca, la encuentran las hitboxes
##
## `zone` permite golpes por zona (cabeza, torso, pies) sin lógica extra:
## se ponen varias hurtboxes sobre el mismo cuerpo con etiquetas distintas.

## Recibió un impacto. El dueño decide daño final, empuje y reacción.
signal wounded(hitbox: Hitbox, hit_position: Vector2)

## Etiqueta de zona. El resolutor de daño la usa como multiplicador.
@export var zone: StringName = &"torso"
## Si es false, la hurtbox se ignora (fase invulnerable, enemigo derrotado).
@export var active: bool = true
## Componente de salud del dueño. Si queda vacío, se busca un hermano llamado
## `HealthComponent` al entrar en el árbol.
@export var health_component: HealthComponent


func _ready() -> void:
	monitoring = false   ## No busca: la encuentran.
	monitorable = true
	if health_component == null:
		var owner_node := get_parent()
		if owner_node != null:
			health_component = owner_node.get_node_or_null("HealthComponent") as HealthComponent


## ¿Este impacto cuenta? Filtra por estado propio y por los i-frames del dueño.
func accepts_hit(_hitbox: Hitbox) -> bool:
	if not active:
		return false
	if health_component != null:
		if health_component.is_dead or health_component.is_invulnerable():
			return false
	return true


## La llama la hitbox atacante a través del resolutor de daño.
func receive(hitbox: Hitbox, hit_position: Vector2) -> void:
	if not accepts_hit(hitbox):
		return
	wounded.emit(hitbox, hit_position)
