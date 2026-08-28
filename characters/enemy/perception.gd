class_name Perception
extends Area2D

## Lo que una entidad ve. Un `Area2D` y nada más.
##
## No conoce `Player` ni comprueba tipos: informa de `Node2D` y filtra por
## capa de colisión, que se configura en la escena (§13). Así sirve igual a un
## enemigo que busca jugadores, a un aliado que busca enemigos o a una trampa
## con sensor — cambiar a quién ve es cambiar la máscara en el inspector, no
## este archivo.

## Alguien entró en el radio.
signal target_entered(target: Node2D)
## Alguien salió del radio.
signal target_exited(target: Node2D)

## Radio de visión. La forma de colisión se regenera a partir de él.
@export var radius: float = 260.0:
	set(value):
		radius = maxf(value, 8.0)
		_rebuild()

var _targets: Array[Node2D] = []
var _shape: CollisionShape2D


func _ready() -> void:
	monitoring = true
	monitorable = false
	_rebuild()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func has_targets() -> bool:
	_forget_invalid()
	return not _targets.is_empty()


## El objetivo visible más cercano a `origin`, o `null`.
func closest_to(origin: Vector2) -> Node2D:
	_forget_invalid()
	var best: Node2D = null
	var best_distance := INF
	for target in _targets:
		var distance := origin.distance_squared_to(target.global_position)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


func _rebuild() -> void:
	if _shape == null:
		_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _shape == null:
		if not is_inside_tree():
			return
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		add_child(_shape)
	var circle := _shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		_shape.shape = circle
	circle.radius = radius


## Un objetivo puede desaparecer sin emitir `body_exited` (se libera dentro del
## radio), así que la lista se limpia antes de usarla.
func _forget_invalid() -> void:
	var vivos: Array[Node2D] = []
	for target in _targets:
		if is_instance_valid(target):
			vivos.append(target)
	_targets = vivos


func _on_body_entered(body: Node2D) -> void:
	if _targets.has(body):
		return
	_targets.append(body)
	target_entered.emit(body)


func _on_body_exited(body: Node2D) -> void:
	_targets.erase(body)
	target_exited.emit(body)
