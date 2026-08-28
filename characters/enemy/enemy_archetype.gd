class_name EnemyArchetype
extends Resource

## Un tipo de enemigo, como datos. Un `.tres` por concepto.
##
## Portado recortado del arquetipo de Tension: allí cargaba además el punto
## crítico, el umbral de daño por embestida y el cooldown de colisión, que eran
## mecánicas de aquel juego y no de este.
##
## **Este recurso es la fuente de verdad de los números del enemigo** (§4). Al
## entrar en el árbol, `Enemy` los reparte entre sus propios componentes hijos
## —salud, stats, tamaño del cuerpo—, que es lo que la excepción de
## orquestación de §2 permite: el anfitrión escribe en lo que le cuelga. La
## alternativa, dejar cada número en el inspector de su componente, obliga a
## tocar seis sitios para crear una variante y no deja duplicar un `.tres`.
##
## Añadir un enemigo nuevo es copiar un `.tres` y cambiar campos: ni una línea
## de código (§13).

@export var display_name: String = "Enemigo"

@export_group("Cuerpo")
## Lado del cuadrado. De aquí salen la forma de colisión, la hurtbox y el
## polígono; no se ajustan a mano en la escena.
@export var body_size: Vector2 = Vector2(44.0, 44.0)
@export var body_color: Color = Color(0.80, 0.28, 0.30, 1.0)

@export_group("Aguante")
@export var max_health: int = 6
## Segundos de invulnerabilidad tras encajar un golpe. Sin esto un combo de
## espada lo vacía en un solo barrido.
@export var invulnerability_seconds: float = 0.25
## Multiplicador del daño recibido. Menor = más duro.
@export var defense: float = 1.0

@export_group("Movimiento")
@export var move_speed: float = 90.0
@export var acceleration: float = 900.0
@export var friction: float = 1200.0
@export var jump_velocity: float = -420.0

@export_group("Vista")
## Radio en el que repara en alguien y lo persigue.
@export var detection_range: float = 260.0
## Distancia a la que abandona la persecución y vuelve. Tiene que ser mayor que
## `detection_range`: si son iguales, el enemigo entra y sale de la persecución
## en cuanto el objetivo se queda justo en el borde.
@export var leash_range: float = 460.0
## Mitad del ancho de la ronda alrededor de donde apareció.
@export var patrol_radius: float = 180.0

@export_group("Ataque")
## Repertorio, en orden de encadenado. Los mismos `AttackData` que usa el
## jugador: un ataque no sabe quién lo asesta.
@export var attacks: Array[AttackData] = []
## A qué distancia horizontal lanza el golpe.
@export var attack_range: float = 52.0
## Segundos entre un ataque y el siguiente.
@export var attack_cooldown: float = 1.1
