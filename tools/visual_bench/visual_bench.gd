extends Node2D

## Banco de pruebas VISUAL: conduce a los dos jugadores por todas las poses.
##
## Existe porque `--write-movie` no tiene teclado y `spectacle` no pilota: sin
## esto, revisar una animación obliga a jugar a mano mientras se graba, y las
## poses que dependen de una situación —caer, encajar un golpe, encadenar el
## combo— no salen cuando toca. Sustituye el `IntentSource` por uno guionizado,
## que es exactamente como conduce la suite de integración, así que lo que se ve
## aquí es el jugador de verdad y no una maqueta.
##
##     godot --path . --scene res://tools/visual_bench/visual_bench.tscn \
##           --write-movie /tmp/b/f.png --fixed-fps 30 --quit-after 270
##
## Luego se monta una tira de fotogramas del tramo que interese y se mira: un
## ciclo de andar invertido, un pie hundido o un arma despegada de la mano no
## salen en ningún assert, y en una tira de seis fotogramas saltan a la vista.
## No es un test y no lo recoge GUT — vive fuera de `tests/` a propósito.

const PlayerScene := preload("res://characters/player/player.tscn")
const SwordKit := preload("res://characters/player/kits/sword_kit.tscn")
const ShieldKit := preload("res://characters/player/kits/shield_kit.tscn")
const Scripted := preload("res://tests/integration/scripted_intent_source.gd")

var espada: Player
var escudo: Player
var i_espada: ScriptedIntentSource
var i_escudo: ScriptedIntentSource
var _t: float = 0.0


func _ready() -> void:
	_suelo()
	espada = _crear(Vector2(-20, 0), SwordKit)
	escudo = _crear(Vector2(70, 0), ShieldKit)
	i_espada = espada.get_node("IntentSource")
	i_escudo = escudo.get_node("IntentSource")
	var cam := Camera2D.new()
	# Encuadre cerrado: un muñeco de 44 px en 1920×1080 no se ve sin zoom, y la
	# cámara tiene que colgar de alguien porque los dos se van andando.
	cam.position = Vector2(30, -38)
	cam.zoom = Vector2(6, 6)
	espada.add_child(cam)
	cam.make_current()


func _crear(donde: Vector2, kit: PackedScene) -> Player:
	var p: Player = PlayerScene.instantiate()
	p.get_node("IntentSource").set_script(Scripted)
	p.get_node("PlayerCamera").queue_free()
	add_child(p)
	p.global_position = donde
	p.equip_kit(kit)
	return p


func _suelo() -> void:
	var cuerpo := StaticBody2D.new()
	var forma := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1200, 40)
	forma.shape = rect
	forma.position = Vector2(0, 20)
	cuerpo.add_child(forma)
	add_child(cuerpo)
	var pintado := Polygon2D.new()
	pintado.polygon = PackedVector2Array([Vector2(-600, 0), Vector2(600, 0),
			Vector2(600, 40), Vector2(-600, 40)])
	pintado.color = Color(0.30, 0.33, 0.38)
	add_child(pintado)


func _physics_process(delta: float) -> void:
	_t += delta
	i_espada.release_all()
	i_escudo.release_all()
	if _t < 2.0:
		pass                                   # idle
	elif _t < 4.5:
		i_espada.set_move(1.0)                 # andar
		i_escudo.set_move(1.0)
	elif _t < 5.2:
		if _t < 4.6:
			i_espada.press_jump()              # saltar y caer
		i_escudo.set_guard(true)
	elif _t < 7.0:
		if fmod(_t, 0.55) < 0.04:
			i_espada.press_attack()            # combo
		i_escudo.set_guard(true)
	elif _t < 8.5:
		i_espada.set_move(-1.0)                # andar de vuelta
		i_escudo.set_move(-1.0)
