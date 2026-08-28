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

	status_label.text = "Hospeda una partida o únete a una."
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
	_set_busy("Esperando al otro jugador…")


func _on_join_pressed() -> void:
	var ip := ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var error := NetworkManager.join(ip)
	if error != OK:
		status_label.text = "No se pudo conectar a %s (error %d)." % [ip, error]
		return
	_set_busy("Conectando con %s…" % ip)


func _on_game_ready(_is_host: bool) -> void:
	# No hay nada que acordar: el reparto de kits es determinista por `peer_id`
	# (host = espada), así que cada peer lo calcula solo. Ver `Session.kit_for`.
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_connection_error(message: String) -> void:
	_set_busy("", false)
	status_label.text = message


func _set_busy(message: String, busy: bool = true) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	ip_field.editable = not busy
	if not message.is_empty():
		status_label.text = message
