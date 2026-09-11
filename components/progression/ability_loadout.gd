class_name AbilityLoadout
extends StatModifierNode

## Traduce el progreso del mundo a los stats de UNA entidad.
##
## Cuelga bajo el `StatsComponent`, que descubre solo a sus `StatModifierNode`
## hijos. No conoce a su dueño ni castea a nadie: sirve igual a un jugador, a un
## enemigo o a una trampa que deba volverse más dura cuando el mundo avanza.
##
## Es UN nodo que devuelve los modificadores de todas las habilidades, y no un
## nodo por habilidad. `StatsComponent._recalculate` recorre sus hijos y llama a
## `get_modifiers()` en cada uno, así que un hijo que devuelve N modificadores es
## indistinguible de N hijos que devuelven uno — y esta forma se ahorra colgar
## nodos desde el `body_entered` de un pedestal, o sea desde dentro del flush de
## queries de física, que es donde Godot prohíbe tocar el árbol de colisiones.
##
## No guarda copia de lo desbloqueado (§4): lo consulta al recalcular. Por eso una
## entidad que entra en el árbol DESPUÉS del desbloqueo no se pierde nada, que es
## la trampa del suscriptor tardío escrita en `AGENTS.md`. El evento solo sirve
## para invalidar la caché, no para enterarse.

func _ready() -> void:
	GameEvents.ability_unlocked.connect(_on_ability_unlocked)


func get_modifiers() -> Array[StatModifierData]:
	var todos: Array[StatModifierData] = []
	for ability in WorldProgress.granted():
		todos.append_array(ability.modifiers)
	return todos


## El `StatsComponent` está suscrito a `modifier_changed` y con esto invalida su
## caché. La habilidad ya está en `WorldProgress` cuando esto llega.
func _on_ability_unlocked(_ability_id: StringName) -> void:
	modifier_changed.emit()
