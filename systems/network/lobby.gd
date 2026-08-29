extends Control

## Lobby mínimo: hospedar o unirse por IP.
##
## Es la única pantalla antes de la partida y, junto con la escena de juego, el
## único sitio que puede llamar a `NetworkManager.host()` / `.join()` (§3). El
## `NetworkManager` no conoce rutas de escena: avisa por señal y es este nodo
## quien decide adónde ir.

const WORLD_SCENE := "res://systems/world/world.tscn"

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var ip_field: LineEdit = %IpField
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	# Volver al lobby debe dejar la sesión anterior limpia.
	NetworkManager.reset()
	SessionState.clear()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.game_ready.connect(_on_game_ready)
	NetworkManager.connection_error.connect(_on_connection_error)
	# Sin esto, una sesión que termina ANTES de entrar en la partida —el host se
	# cae mientras se conecta, o el acuse de carga se rinde— deja los botones
	# deshabilitados y el rótulo en "Conectando…" para siempre, sin decir por qué
	# ni permitir reintentar.
	NetworkManager.session_ended.connect(_on_session_ended)

	# El motivo del fin de la sesión anterior no llega por señal: quien la terminó
	# cambió de escena, y este lobby se acaba de suscribir —o sea, después de que
	# `session_ended` se emitiera—. Se recoge del `NetworkManager`, que lo guardó
	# para esto. Enrutado por el mismo manejador que el caso en vivo, para que los
	# dos caminos no puedan divergir en el texto ni en el estado de los botones.
	var pending := NetworkManager.consume_end_reason()
	if pending.is_empty():
		status_label.text = "Hospeda una partida o únete a una."
	else:
		_on_session_ended(pending)

	# Ojo con el orden: con `--host` o `--join`, lo de abajo sobrescribe el rótulo
	# en el acto y el motivo se gasta sin llegar a verse. Es un atajo de
	# desarrollo y arrancar la sesión importa más que el aviso.
	_apply_command_line()


## Atajos de desarrollo: `--host` y `--join <ip>` arrancan la sesión sin pasar
## por los botones. Sirven para levantar los dos extremos con un solo comando
## y para las pruebas automatizadas de red.
func _apply_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--host"):
		_on_host_pressed.call_deferred()
		return
	var index := args.find("--join")
	if index != -1:
		var ip := "127.0.0.1"
		if index + 1 < args.size():
			ip = args[index + 1]
		ip_field.text = ip
		_on_join_pressed.call_deferred()


func _on_host_pressed() -> void:
	var error := NetworkManager.host()
	if error != OK:
		status_label.text = "No se pudo abrir el puerto %d (error %d)." % [
			NetworkManager.DEFAULT_PORT, error]
		return
	_set_busy("Esperando al otro jugador… (Esc para cancelar)")


func _on_join_pressed() -> void:
	var ip := ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var error := NetworkManager.join(ip)
	if error != OK:
		status_label.text = "No se pudo conectar a %s (error %d)." % [ip, error]
		return
	_set_busy("Conectando con %s… (Esc para cancelar)" % ip)


func _on_game_ready(_is_host: bool) -> void:
	# No hay nada que acordar: el reparto de kits es determinista por `peer_id`
	# (host = espada), así que cada peer lo calcula solo. Ver `SessionState.kit_for`.
	get_tree().change_scene_to_file(WORLD_SCENE)


## La sesión terminó: se devuelve el lobby al jugador y se le dice por qué.
##
## Sirve a los dos casos: la sesión que muere estando ya aquí (llega por señal) y
## la que murió en partida (la trae `_ready`). Se consume el motivo aunque haya
## llegado por señal: si no, se quedaría guardado y aparecería más tarde, en un
## lobby al que ya no le corresponde.
func _on_session_ended(reason: String) -> void:
	NetworkManager.consume_end_reason()
	_set_busy("", false)
	status_label.text = "Sesión terminada: %s." % reason


## Cancelar la espera. Sin esto, hospedar y que no venga nadie era un callejón sin
## salida: los dos botones quedaban deshabilitados, `create_server` no expira, y la
## única forma de salir era matar el proceso.
##
## Se cancela con `reset()` y no con `leave()` a propósito: cancelar no es una
## sesión que se rompe, así que no debe emitir `session_ended` ni contarse como un
## final que haya que explicar.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if not NetworkManager.is_active:
		return
	NetworkManager.reset()
	_set_busy("", false)
	status_label.text = "Se canceló la espera."
	get_viewport().set_input_as_handled()


func _on_connection_error(message: String) -> void:
	_set_busy("", false)
	status_label.text = message


func _set_busy(message: String, busy: bool = true) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	ip_field.editable = not busy
	if not message.is_empty():
		status_label.text = message
