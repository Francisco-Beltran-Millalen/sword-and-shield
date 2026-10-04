extends Node

## Lleva el `AnimationTree` de una entidad a la pose que toca.
##
## Hermano de `state_animator.gd` y su relevo para entidades con arte: aquel
## reproduce una animación suelta en un `AnimationPlayer`, este conduce un
## `AnimationNodeStateMachine` y deja que el motor haga el fundido entre poses
## (§13). El mapa de arquitectura lo pedía así desde que el jugador tuviera arte.
##
## No conoce a `Player`, ni a los kits, ni a la red. Escucha el `StateMachine`
## del anfitrión y, si la tiene, una señal de pose; además lee `velocity` (si el
## anfitrión es un `CharacterBody2D`) para escalar el ciclo de andar y para que
## la capa de PIERNAS decida entre andar y esperar durante `KIT_ACTION`. El
## cuerpo se anima con DOS instancias: una conduce la capa de piernas y otra la
## de torso, cada una con su `playback_parameter` y su mapa `animations`.
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

## Ruta del parámetro de escala del estado `walk` dentro del grafo. La escribe
## `_physics_process` para que el ciclo de andar vaya a la velocidad del cuerpo.
## Cambia en la Fase 2, cuando `walk` se anida bajo la capa de piernas.
@export var walk_scale_parameter: StringName = &"parameters/walk/Escala/scale"

## Velocidad (px/s) a la que el ciclo de andar, reproducido a escala 1, deja el
## pie plantado. Medido conduciendo al jugador: zancada ~8 px por paso y 2 pasos
## por ciclo de 0,6 s → 8 px / 0,3 s ≈ 26,7 px/s. Por debajo o por encima, el
## pie patina; la escala lo corrige (§13: lo hace el motor, no un contador).
@export var walk_reference_speed: float = 26.7

## Tope de la escala del ciclo de andar. Sin él, plantar el pie a la velocidad de
## marcha (220 px/s) exige ~8× y las piernas de 11 px se convierten en un
## parpadeo. Con el tope el ciclo va a una cadencia natural (~6,7 pasos/s a 2×) y
## el pie patina un poco — el compromiso estándar de los metroidvania, y aun así
## patina menos que antes de la Fase 1 (4,62 px/frame → ~2,8 px/frame).
@export var max_walk_scale: float = 2.0

## Estados en los que la velocidad decide entre andar y esperar, en vez del mapa
## de estados. Es la capa de PIERNAS durante `KIT_ACTION`: la guardia sostiene
## `_busy` y el estado se queda en `KIT_ACTION` aunque se ande, así que "ignorar
## ese estado" congelaría las piernas. La pose se toma del mapa (`run_state_key`
## o `idle_state_key`), no se mapea a pelo.
@export var walk_by_velocity_states: Array[int] = []

## Umbral de velocidad horizontal (px/s) por encima del cual "se anda".
@export var walk_velocity_threshold: float = 8.0

## Claves del enum del anfitrión para "andar" y "quieto", de las que sale la
## pose del override por velocidad.
@export var run_state_key: int = 1
@export var idle_state_key: int = 0

## Pose para los estados sin entrada en el mapa. Es el `neutral` de la capa de
## TORSO: durante idle/andar/saltar/caer el tronco no hace nada del kit.
@export var default_pose: StringName = &""

## Parámetro estático que se fija una vez (p. ej. el `blend = 1` del `Blend2`
## que superpone las dos capas). Vacío = no se toca.
@export var blend_parameter: StringName = &""
@export var blend_value: float = 1.0

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


## Escala el ciclo de andar con la velocidad real, acotado por `max_walk_scale`
## para no convertir las piernas en un parpadeo. Lee `velocity` del anfitrión,
## que tiene que ser un `CharacterBody2D` — nunca `Player` (§5: autoconocimiento,
## no dato entre sistemas, y así sirve igual al enemigo de la Fase 4). El motor
## aplica la escala al reproducir; aquí solo se escribe un número (§13).
func _physics_process(_delta: float) -> void:
	var tree := _animation_tree()
	if tree == null:
		return
	if blend_parameter != &"":
		tree.set(blend_parameter, blend_value)
	if walk_reference_speed <= 0.0:
		return
	var cuerpo := _root() as CharacterBody2D
	if cuerpo == null:
		return
	var escala := minf(absf(cuerpo.velocity.x) / walk_reference_speed, max_walk_scale)
	tree.set(walk_scale_parameter, escala)


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


## La pose que pidió el kit gana, si el grafo la conoce; luego el override por
## velocidad; si no, la del estado o la pose por defecto.
func _pose_para(state: int, tree: AnimationTree) -> StringName:
	if _pose != &"" and _grafo_tiene(tree, _pose):
		return _pose
	if state in walk_by_velocity_states:
		var andando := _esta_andando()
		return animations.get(run_state_key if andando else idle_state_key, &"")
	return animations.get(state, default_pose)


func _esta_andando() -> bool:
	var cuerpo := _root() as CharacterBody2D
	return cuerpo != null and absf(cuerpo.velocity.x) > walk_velocity_threshold


func _grafo_tiene(tree: AnimationTree, pose: StringName) -> bool:
	return _buscar_nodo(tree.tree_root, pose)


## Busca un nodo de state machine a cualquier profundidad: con el grafo anidado
## (`BlendTree` raíz con `Piernas` y `Torso`), la pose no cuelga de la raíz.
func _buscar_nodo(nodo: AnimationNode, nombre: StringName) -> bool:
	var machine := nodo as AnimationNodeStateMachine
	if machine != null and machine.has_node(nombre):
		return true
	var arbol := nodo as AnimationNodeBlendTree
	if arbol == null:
		return false
	for hijo in arbol.get_node_list():
		if hijo == &"output":
			continue
		if _buscar_nodo(arbol.get_node(hijo), nombre):
			return true
	return false


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
