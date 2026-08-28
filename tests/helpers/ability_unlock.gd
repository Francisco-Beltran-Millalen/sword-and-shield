class_name AbilityUnlock
extends StatModifierNode

## Desbloqueo de habilidad para los tests: un `StatModifierNode` que aporta los
## modificadores que se le pidan.
##
## Es la forma que tendrá una habilidad real del metroidvania — adquirir el
## doble salto será instanciar un nodo así bajo el `StatsComponent`, sin tocar
## ni una línea del jugador.

var modifiers: Array[StatModifierData] = []


func get_modifiers() -> Array[StatModifierData]:
	return modifiers


## Atajo: concede `amount` saltos aéreos.
static func air_jumps(amount: float) -> AbilityUnlock:
	var unlock := AbilityUnlock.new()
	unlock.modifiers = [
		StatModifierData.new(StatsComponent.StatID.AIR_JUMPS, amount, 1.0)
	]
	return unlock
