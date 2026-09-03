class_name AbilityCatalogue
extends Resource

## Todas las habilidades que existen en el juego, en un solo recurso.
##
## Existe para que ni la red ni el guardado tengan que mover rutas de recurso.
## Por el cable y al archivo va un `ability_id`; quien necesite los datos los pide
## aquí. Un id que no esté en el catálogo no resuelve — que es exactamente lo que
## se quiere cuando el id llega de fuera.
##
## Es un `.tres` y no un barrido de `components/progression/abilities/*.tres` a
## propósito: `DirAccess` sobre `res://` no es fiable en un build exportado, donde
## los recursos viajan empaquetados y renombrados. Un catálogo explícito se
## exporta como cualquier otro recurso y además se ve en el inspector.

@export var abilities: Array[AbilityData] = []


## La habilidad con ese id, o `null`. Devolver `null` es una respuesta válida:
## la usan los avisos de configuración para cazar un id mal escrito en el editor.
func find(ability_id: StringName) -> AbilityData:
	for candidate in abilities:
		if candidate != null and candidate.ability_id == ability_id:
			return candidate
	return null
