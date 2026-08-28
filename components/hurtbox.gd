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
		# `owner` (la raíz de la escena) y no `get_parent()`: una hurtbox por
		# zona cuelga de un Node2D intermedio, y buscar en el padre no
		# encontraba nada —aceptando entonces TODOS los golpes e ignorando los
		# i-frames, en silencio. Ese caso por zonas es justo el que promete el
		# campo `zone` de más abajo.
		var host: Node = owner if owner != null else get_parent()
		if host != null:
			health_component = host.get_node_or_null("HealthComponent") as HealthComponent
		if health_component == null:
			push_warning("Hurtbox '%s' sin HealthComponent: asígnalo en el inspector o los i-frames no se respetarán." % name)


## De quién es esta hurtbox. `owner` y no `get_parent()`: en golpes por zona la
## hurtbox cuelga de un `Node2D` intermedio y el padre no es la entidad. Lo
## necesita quien atribuya el golpe — un HUD, el aggro de un enemigo, el bus de
## eventos.
func entity() -> Node:
	return owner if owner != null else get_parent()


## ¿Este impacto cuenta? Filtra por estado propio y por los i-frames del dueño.
func accepts_hit(_hitbox: Node) -> bool:
	if not active:
		return false
	if health_component != null:
		if health_component.is_dead or health_component.is_invulnerable():
			return false
	return true


## La llama la hitbox atacante a través del resolutor de daño.
func receive(hitbox: Node, hit_position: Vector2) -> void:
	if not accepts_hit(hitbox):
		return
	wounded.emit(hitbox, hit_position)
