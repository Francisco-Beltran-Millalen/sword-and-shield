extends CanvasLayer

## Panel de depuración: qué está pasando, mientras pasa.
##
## Existe porque la acción `debug_overlay` (F3) llevaba en el InputMap desde el
## primer commit sin que nadie la leyera, y porque los dos fallos que quedan
## abiertos —el gesto del enemigo en el peer remoto y el golpe que no anuncia—
## **sólo existen con dos procesos**: no hay test que los cace, y sin números en
## pantalla la única alternativa es deducirlos.
##
## **No conoce a nadie**, igual que el `Hud`: ni busca jugadores, ni guarda
## referencias a entidades, ni pregunta por el árbol. Lo que sabe le llega por
## dos vías, y cada una por su motivo (§1):
##
##   - La **zona** se la empuja el `World`, que es su padre y la carga él (§5).
##   - La **sala** y los **golpes** llegan por `GameEvents`, porque sus emisores
##     —`RoomBounds` dentro de la zona, `Attacker` dentro de un kit— no pueden
##     conocer a un nodo que cuelga del `World`. Ésa es la primera condición de
##     admisión del bus, y aquí se cumple de verdad.
##
## No es un autoload (§9): no guarda estado del juego, y muere con la escena que
## lo monta, que es lo que se quiere de una herramienta.

## Arrancar visible. `--write-movie` no tiene teclado —es la forma de mirar el
## juego que documenta AGENTS.md—, así que un overlay que sólo se enciende con
## F3 no sale en una sola grabación, que es justo cuando hace falta.
@export var visible_al_arrancar: bool = false

## Cuántos golpes recordar en el marcador.
const HISTORIAL: int = 6

var _zona: StringName = &""
var _sala: StringName = &""
var _golpes: int = 0
var _guardias: int = 0
var _ultimos: Array[String] = []

@onready var _texto: Label = %Texto


func _ready() -> void:
	_mostrar(visible_al_arrancar)
	GameEvents.room_entered.connect(_on_room_entered)
	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.hit_guarded.connect(_on_hit_guarded)
	_repintar()


## La zona la empuja el `World` al cargarla, como la salud al `Hud`.
func set_zone(zone_id: StringName) -> void:
	_zona = zone_id
	_repintar()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"debug_overlay"):
		return
	get_viewport().set_input_as_handled()
	_mostrar(not visible)


## Un `CanvasLayer` NO es un `CanvasItem`: no tiene
## `NOTIFICATION_VISIBILITY_CHANGED`, así que no hay forma de enterarse de que lo
## han escondido. Se enciende y se apaga por aquí, y de paso se apaga el proceso:
## invisible, este nodo no cuesta un frame.
func _mostrar(encendido: bool) -> void:
	visible = encendido
	set_process(encendido)


func _process(_delta: float) -> void:
	# Sólo se repinta lo que cambia cada frame cuando se está mirando: apagado,
	# el nodo no hace nada. Lo apaga el motor, no un `if` (§13).
	_repintar()


func _on_room_entered(room_id: StringName) -> void:
	_sala = room_id
	_repintar()


func _on_hit_landed(attacker: Node, target: Node, damage: int) -> void:
	_golpes += 1
	_anotar("golpe %s → %s (%d)" % [_nombre(attacker), _nombre(target), damage])


func _on_hit_guarded(guard: Node, attacker: Node, perfect: bool) -> void:
	_guardias += 1
	_anotar("%s: %s ← %s" % ["parry" if perfect else "guardia",
			_nombre(guard), _nombre(attacker)])


## El nombre del nodo, o "?" si el evento vino sin él. Un golpe encaminado por
## RPC llega sin atacante: un `Node` no se serializa, y verlo aquí en blanco es
## precisamente el dato.
func _nombre(node: Node) -> String:
	return node.name if node != null else "?"


func _anotar(linea: String) -> void:
	_ultimos.push_front(linea)
	while _ultimos.size() > HISTORIAL:
		_ultimos.pop_back()
	_repintar()


func _repintar() -> void:
	if _texto == null:
		return
	var lineas := PackedStringArray()
	lineas.append("%d fps" % Engine.get_frames_per_second())
	lineas.append("zona  %s" % (_zona if _zona != &"" else "—"))
	lineas.append("sala  %s" % (_sala if _sala != &"" else "—"))
	lineas.append(_red())
	lineas.append("golpes %d · guardias %d" % [_golpes, _guardias])
	for linea in _ultimos:
		lineas.append("  " + linea)
	_texto.text = "\n".join(lineas)


## Las dos preguntas de red, separadas como manda el proyecto: si hay sesión lo
## dice `NetworkManager.is_active`, y quién soy, el peer.
func _red() -> String:
	if not NetworkManager.is_active:
		return "red   sin sesión (peer %d)" % multiplayer.get_unique_id()
	return "red   %s · peer %d" % [
		"host" if multiplayer.is_server() else "cliente",
		multiplayer.get_unique_id(),
	]
