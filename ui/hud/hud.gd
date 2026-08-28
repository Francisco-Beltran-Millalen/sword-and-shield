class_name Hud
extends CanvasLayer

## Panel de lectura de la partida: la salud de cada jugador y por qué una puerta
## no se abre.
##
## **No conoce a nadie.** Recibe enteros por métodos públicos y los pinta: no
## busca jugadores, no guarda referencias a entidades y no se suscribe a nada.
## Quien tiene delante a los dos jugadores y a la zona es el `World`, y es él
## quien empuja (§5: el contexto de coordinación se empuja, no se consulta). Eso
## es lo que la constitución llama "capa UI, solo lectura", y no un sistema más.
##
## La ventaja es de ciclo de vida, no de purismo. Sin suscripciones propias, un
## jugador que se desconecta o una zona que se descarga no dejan aquí punteros
## muertos ni avisos pegados de algo que ya no existe.

## Ranuras de salud: la propia arriba, la del compañero debajo. Quién ocupa cada
## una lo decide el `World`, que es el único que sabe qué peer es este.
enum Slot { SELF, PARTNER }

@onready var _rows: Array[Control] = [%SelfRow as Control, %PartnerRow as Control]
@onready var _bars: Array[ProgressBar] = [
	%SelfHealth as ProgressBar, %PartnerHealth as ProgressBar,
]
@onready var _names: Array[Label] = [%SelfName as Label, %PartnerName as Label]
@onready var _door_notice: Label = %DoorNotice


func _ready() -> void:
	# Se arranca en blanco: una ranura solo aparece cuando el `World` la llena.
	for slot in range(_rows.size()):
		clear_slot(slot)
	set_door_wait(0, 0)


## Pinta la salud de una ranura.
func set_health(current: int, maximum: int, slot: int) -> void:
	if not _has_slot(slot):
		return
	var bar := _bars[slot]
	bar.max_value = maxi(maximum, 1)
	bar.value = clampi(current, 0, maximum)
	_rows[slot].visible = true


## Rótulo de una ranura: el kit que lleva ese jugador.
func set_slot_label(text: String, slot: int) -> void:
	if not _has_slot(slot):
		return
	_names[slot].text = text
	_rows[slot].visible = true


## La ranura deja de mostrarse porque su jugador se fue del árbol.
func clear_slot(slot: int) -> void:
	if not _has_slot(slot):
		return
	_rows[slot].visible = false


## Cuánta gente hay en la puerta y cuánta hace falta para cruzar.
##
## `required <= 0` apaga el aviso, que es lo que manda el `World` al cambiar de
## zona: el aviso no puede sobrevivir a la puerta que lo pidió.
func set_door_wait(present: int, required: int) -> void:
	var faltan_jugadores := required > 0 and present > 0 and present < required
	_door_notice.visible = faltan_jugadores
	if faltan_jugadores:
		_door_notice.text = "Esperando al otro jugador — %d/%d" % [present, required]


func _has_slot(slot: int) -> bool:
	return slot >= 0 and slot < _rows.size()
