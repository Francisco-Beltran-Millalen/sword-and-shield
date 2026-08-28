class_name IntentSource
extends Node

## De dónde salen las intenciones de un jugador.
##
## Tres implementaciones previstas, intercambiables sin que nada aguas abajo
## se entere: `LocalIntentSource` (teclado/mando), una fuente de red que
## reconstruye el intent desde RPC, y `ScriptedIntentSource` en los tests.
##
## Este es el único lugar del proyecto donde puede aparecer `Input.*` (§8).

var _intent := PlayerIntent.new()


## Devuelve el intent de este frame. La instancia se reutiliza: quien la reciba
## debe leerla en el acto, no guardarla.
func poll() -> PlayerIntent:
	return _intent
