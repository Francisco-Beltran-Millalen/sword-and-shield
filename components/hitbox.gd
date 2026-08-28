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

var _touched: Array[int] = []
var _attacker: Node = null


## Quién asesta el golpe: el primer `CharacterBody2D` por encima en el árbol.
## No se usa `owner` — en Godot esa propiedad es el nodo raíz de la escena donde
## se guardó el nodo, que no tiene por qué ser el atacante.
func attacker() -> Node:
	if _attacker != null and is_instance_valid(_attacker):
		return _attacker
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody2D:
			_attacker = node
			return _attacker
		node = node.get_parent()
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

	var guard := area as GuardBox
	if guard != null:
		if guard.blocks(self):
			_touched.append(area.get_instance_id())
			guarded.emit(guard, area.global_position)
			return

	var hurtbox := area as Hurtbox
	if hurtbox == null or not hurtbox.accepts_hit(self):
		return

	_touched.append(area.get_instance_id())
	hit.emit(hurtbox, area.global_position)
