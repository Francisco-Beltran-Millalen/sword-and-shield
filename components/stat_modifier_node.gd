class_name StatModifierNode
extends Node

## Fuente de modificadores de stats. Cualquier nodo que quiera alterar los stats
## de una entidad hereda de esta clase y se cuelga como hijo del
## `StatsComponent`, que lo descubre solo y escucha `modifier_changed`.
##
## El origen del modificador es indiferente para el componente: un objeto
## equipado, una habilidad desbloqueada, un buff temporal o un efecto de terreno
## se expresan todos igual. Emite `modifier_changed` cuando tus modificadores
## cambien; el componente invalida su caché y recalcula perezosamente.

@warning_ignore("unused_signal")
signal modifier_changed


## Sobrescribir en subclases. Devuelve los modificadores que este nodo aporta
## en este momento.
func get_modifiers() -> Array[StatModifierData]:
	return []
