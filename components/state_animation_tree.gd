extends Node

## Lleva el `AnimationTree` de una entidad a la pose que toca.
##
## Hermano de `state_animator.gd` y su relevo para entidades con arte: aquel
## reproduce una animación suelta en un `AnimationPlayer`, este conduce un
## `AnimationNodeStateMachine` y deja que el motor haga el fundido entre poses
## (§13). El mapa de arquitectura lo pedía así desde que el jugador tuviera arte.
##
## No conoce a `Player`, ni a los kits, ni a la red. Escucha dos cosas del
## anfitrión —su `StateMachine` y, si la tiene, una señal de pose— y ambas le
## llegan igual si las produce la simulación local o un paquete replicado.
##
## POR QUÉ HAY DOS FUENTES y no sólo el estado: `Player.State.KIT_ACTION` es un
## único estado para atacar Y guardar, y el combo son tres golpes bajo ese mismo
## estado. Un mapa estado → pose enseñaría siempre la primera estocada y nunca la
## guardia. La señal de pose la emite quien sí lo sabe (el kit, hacia arriba por
## su dueño); aquí sólo se recibe un `StringName`.

## Sin `class_name`: una clase global obliga a reimportar antes de que compile
## quien la usa, y un script que no compila deja al nodo SIN script sin romper la
## escena (trampa nº1 de `AGENTS.md`). Se precarga por ruta, como `ComponentLookup`.
const ComponentLookup := preload("res://components/component_lookup.gd")

## Estado → nombre del nodo en el `AnimationNodeStateMachine`. Las claves son los
## enteros del enum del anfitrión; un estado sin entrada no cambia la pose.
@export var animations: Dictionary[int, StringName] = {}

## Dónde buscar el `StateMachine` y el `AnimationTree`. Vacío = el padre.
@export var target: Node

## Señal opcional del anfitrión que anuncia una pose concreta, con firma
## `(pose: StringName)`. Una pose vacía significa "vuelve a mandar el estado".
@export var pose_signal: StringName = &"pose_changed"

## Dónde vive el playback del state machine raíz. Cambia si el grafo se anida.
@export var playback_parameter: StringName = &"parameters/playback"

var _machine: StateMachine
## Última pose pedida por señal. Manda sobre el mapa de estados mientras exista.
var _pose: StringName = &""


func _ready() -> void:
	var root := _root()
	if root == null:
		return
	_machine = ComponentLookup.find(root, "StateMachine", "Node") as StateMachine
	if _machine == null:
		push_warning("StateAnimationTree sin StateMachine: no animará nada.")
		return
	_machine.state_changed.connect(_on_state_changed)
	if pose_signal != &"" and root.has_signal(pose_signal):
		root.connect(pose_signal, _on_pose_changed)
	# `init_state` no emite nada, así que nadie anunciará la pose de arranque:
	# quien se suscribe tarde no ve el primer valor (`AGENTS.md`). Se pide aquí.
	# Diferida porque el `_ready` de este nodo puede correr antes que el del
	# `AnimationTree`, que es nieto del anfitrión y no hermano de este.
	_aplicar.call_deferred(_machine.current_state, false)


func _on_state_changed(_from: int, to: int) -> void:
	_aplicar(to, false)


## Una pose repetida SÍ reinicia: el segundo golpe de un combo no cambia de
## estado —sigue en `KIT_ACTION`— y sin reinicio el cuerpo se quedaría quieto
## mientras el arma sí repite su gesto.
func _on_pose_changed(pose: StringName) -> void:
	_pose = pose
	_aplicar(_machine.current_state if _machine != null else -1, true)


func _aplicar(state: int, reiniciar: bool) -> void:
	var tree := _animation_tree()
	if tree == null:
		return
	var playback := tree.get(playback_parameter) as AnimationNodeStateMachinePlayback
	if playback == null:
		return
	var pose := _pose_para(state, tree)
	if pose == &"":
		return
	if playback.get_current_node() != pose:
		playback.travel(pose)
		return
	if reiniciar:
		# `start` rearranca desde el fotograma cero; `travel` a la pose en curso
		# no hace nada.
		playback.start(pose)


## La pose que pidió el kit gana, si el grafo la conoce; si no, la del estado.
func _pose_para(state: int, tree: AnimationTree) -> StringName:
	if _pose != &"" and _grafo_tiene(tree, _pose):
		return _pose
	return animations.get(state, &"")


func _grafo_tiene(tree: AnimationTree, pose: StringName) -> bool:
	var raiz := tree.tree_root
	if raiz == null or not raiz.has_method("has_node"):
		return false
	return raiz.call("has_node", pose)


func _root() -> Node:
	return target if target != null else get_parent()


## Se resuelve en cada uso, sin cachear: es la misma razón que en
## `state_animator.gd` —el árbol de una entidad puede reemplazarse en caliente—
## y aquí además el `AnimationTree` cuelga de los visuales, no del anfitrión.
func _animation_tree() -> AnimationTree:
	var root := _root()
	if root == null:
		return null
	return ComponentLookup.find(root, "AnimationTree", "AnimationTree") as AnimationTree
