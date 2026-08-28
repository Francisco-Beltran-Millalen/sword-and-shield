class_name AttackData
extends Resource

## Un ataque, como datos. Un `.tres` por golpe.
##
## Añadir un ataque —o un enemigo con otro repertorio— es crear recursos y
## asignarlos en el inspector, sin tocar código (§13). Nada aquí sabe quién
## ataca: sirve igual para el kit de espada de un jugador, para un enemigo o
## para una trampa.
##
## Los tiempos de la ventana activa NO están aquí: los marca la animación con
## pistas de método sobre el `Attacker`. Este recurso describe *qué* hace el
## golpe, no *cuándo* — el cuándo es del `AnimationPlayer`.

## Animación que reproduce este ataque. Debe existir en la biblioteca asignada
## al `AnimationPlayer` de la entidad.
@export var animation: StringName = &"attack_1"

@export_group("Efecto")
@export var damage: int = 1
## Empuje aplicado a quien lo recibe.
@export var knockback: float = 320.0
## Etiqueta libre para que el receptor pueda tratar golpes distinto
## (`&"light"`, `&"heavy"`, `&"thrust"`). No la interpreta el atacante.
@export var attack_id: StringName = &"light"
## Cuántas víctimas distintas alcanza una activación. 1 = golpe único.
@export var max_targets: int = 1

@export_group("Movimiento")
## Impulso hacia delante al iniciar el golpe. 0 = el ataque no desplaza.
@export var lunge_speed: float = 0.0

@export_group("Encadenado")
## Si es `true`, pulsar otra vez durante el golpe encadena al siguiente ataque
## de la lista del `Attacker`. Si es `false`, el ataque no encadena.
@export var chains: bool = true
