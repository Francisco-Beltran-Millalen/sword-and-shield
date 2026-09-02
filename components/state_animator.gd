extends Node

## Reproduce una animación cuando su entidad cambia de estado.
##
## Existe por un fallo que sólo se ve con dos procesos: al enemigo lo simula el
## host, `Enemy._physics_process` corta sin autoridad y es el `Attacker` quien
## lanza la animación, así que **el cliente lo veía golpear sin gesto**. El
## estado sí viaja (`replicated_state`), y su llegada dispara `state_changed` en
## el peer remoto: eso es lo que este nodo escucha.
##
## No sabe de red. Escucha cambios de estado, vengan de la simulación local o de
## un paquete, y por eso sirve igual en los dos extremos y en un test sin red.
##
## ALCANCE, dicho en voz alta: hoy resuelve el **enemigo**, que tiene un estado
## de ataque y una animación. **No resuelve al jugador** y no se le cuelga:
## `Player.State.KIT_ACTION` es un solo estado para ataque *y* guardia, y su
## combo son tres animaciones bajo ese mismo estado, así que un mapa
## estado → animación mostraría siempre el primer mandoble. Para el jugador el
## mapa de arquitectura ya pide un `AnimationTree` en modo StateMachine, y sigue
## aplazado a que haya arte.

## Sin `class_name`: `ComponentLookup` renunció al suyo por la misma razón —una
## clase global obliga a reimportar antes de que compile quien la usa— y se
## precarga por ruta, que es el patrón del repo.
const ComponentLookup := preload("res://components/component_lookup.gd")

## Estado → animación. Las claves son los enteros del enum de la entidad; un
## estado sin entrada simplemente no anima, que es lo normal mientras no haya
## arte para caminar o estar quieto.
@export var animations: Dictionary[int, StringName] = {}

## Dónde buscar el `StateMachine` y el `AnimationPlayer`. Vacío = el padre.
@export var target: Node

var _machine: StateMachine


func _ready() -> void:
	var root := target if target != null else get_parent()
	if root == null:
		return
	_machine = ComponentLookup.find(root, "StateMachine", "Node") as StateMachine
	if _machine == null:
		push_warning("StateAnimator sin StateMachine: no animará nada.")
		return
	_machine.state_changed.connect(_on_state_changed)


func _on_state_changed(_from: int, to: int) -> void:
	if not animations.has(to):
		return
	var player := _animation_player()
	if player == null:
		return
	var wanted: StringName = animations[to]
	if not player.has_animation(wanted):
		return
	# Si ya está sonando, no se reinicia. En el peer que simula, el `Attacker` la
	# ha lanzado una línea antes de que el estado cambie; volver a llamar a
	# `play()` la rearrancaría desde cero y movería las pistas que abren y
	# cierran la ventana de daño.
	if player.current_animation == wanted:
		return
	player.play(wanted)


## Se resuelve en cada uso y no se cachea en `_ready`. En el jugador el único
## `AnimationPlayer` vive dentro del **kit**, que se instala en runtime y se
## reemplaza al cambiar de kit: una referencia guardada apuntaría a un nodo con
## `queue_free()` ya pedido.
func _animation_player() -> AnimationPlayer:
	var root := target if target != null else get_parent()
	if root == null:
		return null
	return ComponentLookup.find(root, "AnimationPlayer", "AnimationPlayer") as AnimationPlayer
