class_name AbilityData
extends Resource

## Una habilidad del metroidvania, como DATO y no como código (§13: los datos del
## juego son un `Resource` con `@export`, igual que `AttackData`).
##
## Una habilidad es progreso del **mundo**, no de la persona: al desbloquearse la
## tienen los dos jugadores. Se deriva de dos decisiones ya tomadas y no de una
## preferencia — el guardado es "del host, un archivo, estado del mundo, sin
## guardado por jugador", y `ZoneDoor.required_players = 2` impide que los
## jugadores se separen entre zonas, así que no hay forma de que uno progrese sin
## el otro. Ver `ARCHITECTURE-MAP.md` → *Deferred*, fila del sistema de guardado.
##
## Hoy una habilidad es un puñado de números que se suman a los stats. El día que
## una traiga piezas propias —un dash con su hitbox y su temporizador— aquí entra
## un `node_scene: PackedScene` que el `AbilityLoadout` instancia, que es lo que
## §2 pide para una capacidad. Queda anotado con su disparador en el mapa; hoy
## construirlo sería especulativo.

## Identificador estable. Es lo ÚNICO que viaja por la red y lo único que
## escribirá el guardado: nunca una ruta de recurso. Un `.tres` puede referenciar
## un script, así que cargar una ruta que venga de un archivo de usuario es
## ejecución de código arbitrario. La resolución id → recurso la hace
## `AbilityCatalogue`, que vive en el proyecto y no en el disco del jugador.
@export var ability_id: StringName = &""

## Nombre para el jugador. Lo pinta el HUD cuando una puerta no se abre.
@export var display_name: String = ""

## Qué le hace a los stats de quien la tiene.
@export var modifiers: Array[StatModifierData] = []
