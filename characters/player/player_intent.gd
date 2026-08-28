class_name PlayerIntent
extends RefCounted

## Lo que el jugador QUIERE hacer este frame, sin decir de dónde viene.
##
## Es la frontera de red (§10). Un intent se produce de tres formas —teclado
## local, llegada por RPC desde el peer remoto, o un guion de test— y a partir
## de ahí nada aguas abajo distingue el origen.
##
## El proyecto anterior declaró esta clase pero nunca la enhebró: su broker
## acabó con dos ramas de ~40 líneas cada una que asignaban los mismos campos,
## una para input local y otra para red. Aquí el intent es el único camino.

## Eje horizontal, -1..1.
var move: float = 0.0
## Ejes verticales sostenidos, 0..1. Sirven para plataformas atravesables
## (abajo), miradas hacia arriba y anclajes direccionales.
var up: float = 0.0
var down: float = 0.0

## Flancos de subida: verdaderos solo el frame en que se pulsó.
var jump_pressed: bool = false
var attack_pressed: bool = false
var tether_pressed: bool = false
var interact_pressed: bool = false

## Estados sostenidos.
var jump_held: bool = false
var guard_held: bool = false


## Copia los valores de otro intent. Reutilizar la instancia evita una
## asignación por frame y por jugador.
func copy_from(other: PlayerIntent) -> void:
	move = other.move
	up = other.up
	down = other.down
	jump_pressed = other.jump_pressed
	attack_pressed = other.attack_pressed
	tether_pressed = other.tether_pressed
	interact_pressed = other.interact_pressed
	jump_held = other.jump_held
	guard_held = other.guard_held


## Limpia los flancos tras consumirlos, conservando los sostenidos.
func clear_edges() -> void:
	jump_pressed = false
	attack_pressed = false
	tether_pressed = false
	interact_pressed = false


## Dirección de encaramiento derivada del movimiento: -1, 0 o 1.
func facing() -> int:
	if absf(move) < 0.1:
		return 0
	return signi(int(signf(move)))
