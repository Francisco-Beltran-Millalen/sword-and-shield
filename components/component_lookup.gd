extends RefCounted

## Cómo una entidad encuentra sus propias piezas.
##
## Sin `class_name` a propósito: no aporta ningún tipo, solo una función
## estática, y registrar una clase global obliga a reimportar antes de que los
## scripts que la usan vuelvan a compilar. Un script que no compila deja al nodo
## SIN script sin romper la instanciación de la escena, y la suite sigue en
## verde — la trampa nº1 de `CLAUDE.md`. Los consumidores lo precargan por ruta:
##
##     const ComponentLookup := preload("res://components/component_lookup.gd")
##
## Existía tres veces, divergiendo. `Attacker` buscaba por nombre y luego por
## tipo; `DamageReceiver` y `Hurtbox`, solo por nombre literal. Esa diferencia no
## era cosmética: `Hurtbox` documenta como caso soportado que una hurtbox por
## zona cuelgue de un `Node2D` intermedio, y en esa estructura el
## `DamageReceiver` no la encontraba, avisaba con un `push_warning` y la entidad
## se quedaba inmune en silencio.

## Busca una pieza bajo `root`: primero un hijo con ese nombre y, si no aparece,
## el primer nodo de ese tipo en cualquier profundidad.
##
## La segunda pasada es la que permite que un componente sirva a estructuras de
## escena distintas. En el enemigo la hitbox cuelga del nodo de visuales, que es
## lo que se voltea al cambiar de lado; una hitbox hija directa del
## `CharacterBody2D` no tendría desde dónde voltearse y el bicho solo golpearía a
## la derecha. Buscar por tipo es lo que hace que eso no obligue a tocar código.
##
## `owned = false` en `find_children` a propósito: un componente construido por
## código —los maniquíes de los tests, un enemigo montado a mano— no tiene
## `owner`, y filtrar por él lo dejaría fuera.
static func find(root: Node, node_name: String, type_name: String) -> Node:
	if root == null:
		return null
	var direct := root.get_node_or_null(node_name)
	if direct != null:
		return direct
	var found := root.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null
