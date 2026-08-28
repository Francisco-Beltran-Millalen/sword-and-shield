class_name Hitbox
extends Area2D

## Volumen que INFLIGE daño mientras está activo.
##
## Apagado por defecto: `monitoring` arranca en false y se enciende solo durante
## los frames activos del ataque. Quien lo enciende es la pista de método del
## `AnimationPlayer` (`enable()` / `disable()`), no un contador de frames en
## GDScript — el proyecto anterior tenía cinco contadores a mano y ninguna
## animación (§13: el motor primero).
##
## Configuración en el editor:
##   - `collision_layer` → la capa propia (`player_hitbox` o `enemy_hitbox`)
##   - `collision_mask`  → las capas que puede golpear (`enemy_hurtbox`, `guard`…)
##
## Nunca aplica daño directamente sobre la víctima: emite `hit` y deja que el
## dueño decida (§2 — nada de escribir estado ajeno).

## Conectó contra una hurtbox. `hit_position` es el punto de contacto aproximado.
signal hit(hurtbox: Hurtbox, hit_position: Vector2)
## Conectó contra una guardia activa.
signal guarded(guard: GuardBox, hit_position: Vector2)

@export var damage: int = 1
## Empuje aplicado a la víctima, en la dirección del golpe.
@export var knockback: float = 320.0
## Etiqueta del ataque (`&"light"`, `&"heavy"`, `&"pommel"`). El resolutor de
## daño puede tratarlos distinto sin que la hitbox sepa de reglas.
@export var attack_id: StringName = &"light"
## Cuántas víctimas distintas puede tocar una misma activación. 1 = golpe único.
@export var max_targets: int = 1

## Quién asesta el golpe. Vacío = se deduce (ver `attacker()`). Explicitarlo es
## lo que permite que ataque algo que no es un cuerpo cinemático: una trampa
## estática, una torreta, un proyectil.
@export var source: Node

var _touched: Array[int] = []
var _attacker: Node = null


## Quién asesta el golpe, para atribuir el daño.
##
## Orden: `source` si se asignó; si no, `owner` (la raíz de la escena donde vive
## esta hitbox, que en una trampa o un proyectil ES el atacante); y como último
## recurso el primer padre del grupo `combat_source`.
##
## Antes esto exigía un `CharacterBody2D` por encima, lo que dejaba fuera a toda
## entidad que no fuera un cuerpo cinemático — y fallaba en silencio,
## atribuyendo el daño a `null`.
func attacker() -> Node:
	if _attacker != null and is_instance_valid(_attacker):
		return _attacker
	if source != null:
		_attacker = source
		return _attacker
	if owner != null:
		_attacker = owner
		return _attacker
	var node: Node = get_parent()
	while node != null:
		if node.is_in_group(&"combat_source"):
			_attacker = node
			return _attacker
		node = node.get_parent()
	push_warning("Hitbox sin atacante identificable: asigna `source` o marca al dueño en el grupo `combat_source`.")
	return null


func _ready() -> void:
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)


## Enciende la hitbox. Llamar desde una pista de método del AnimationPlayer en
## el primer frame activo del ataque.
func enable() -> void:
	_touched.clear()
	monitoring = true


## Apaga la hitbox. Llamar en el frame en que termina la ventana activa.
func disable() -> void:
	monitoring = false
	_touched.clear()


func is_active() -> bool:
	return monitoring


## Dirección del golpe hacia `target`, usada para el empuje. Horizontal pura si
## los cuerpos están casi alineados, para que un golpe lateral no lance al cielo.
func direction_to(target: Node2D) -> Vector2:
	var delta := target.global_position - global_position
	if absf(delta.x) < 1.0:
		return Vector2(signf(scale.x), 0.0)
	return delta.normalized()


func _on_area_entered(area: Area2D) -> void:
	if _touched.size() >= max_targets:
		return

	# Se pregunta por el CONTRATO, no por la clase. Así una barrera destructible,
	# una armadura por piezas o un escudo de jefe participan sin que haya que
	# tocar este archivo (§7).
	if area.has_method("covers") and area.covers(self):
		_touched.append(area.get_instance_id())
		if area.has_method("register_block"):
			area.register_block(self)
		guarded.emit(area, area.global_position)
		return

	if not area.has_method("accepts_hit") or not area.accepts_hit(self):
		return

	_touched.append(area.get_instance_id())
	# Se avisa a la víctima por su API pública (§2: llamar un método, no escribir
	# su estado). Sin esta línea la cadena quedaba abierta: la hitbox detectaba
	# el contacto y emitía `hit` para su dueño, pero la hurtbox nunca emitía
	# `wounded`, así que el daño no llegaba a aplicarse nunca.
	if area.has_method("receive"):
		area.receive(self, area.global_position)
	hit.emit(area, area.global_position)
