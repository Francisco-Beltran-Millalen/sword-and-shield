extends GutTest

## El gesto que se ve en el peer que NO simula.
##
## Al enemigo lo simula el host: `Enemy._physics_process` corta sin autoridad y
## es el `Attacker` quien lanza la animación, así que el cliente lo veía golpear
## sin mover un dedo. Se arregla animando por ESTADO, que es lo que sí viaja.
##
## Aquí no hay red —montar dos peers en un test es otro problema— y no hace
## falta: el peer remoto no tiene nada especial, sólo recibe el estado en vez de
## calcularlo. Escribir `replicated_state` es exactamente lo que le pasa al
## llegar el paquete, así que eso es lo que se prueba.

const AnimatorScript := preload("res://components/state_animator.gd")
const MachineScript := preload("res://components/state_machine.gd")
const AttackerScript := preload("res://components/combat/attacker.gd")
const HitboxScript := preload("res://components/hitbox.gd")
const EnemyAnimations := preload("res://characters/enemy/enemy_animations.tres")
const EnemyScene := preload("res://characters/enemy/enemy.tscn")

enum { QUIETO, ANDANDO, GOLPEANDO }

var _entidad: Node2D
var _machine: StateMachine
var _player: AnimationPlayer
var _animator: Node


func before_each() -> void:
	_entidad = _montar_entidad()
	add_child_autofree(_entidad)

	_machine = _entidad.get_node("StateMachine") as StateMachine
	_player = _entidad.get_node("AnimationPlayer") as AnimationPlayer

	_animator = AnimatorScript.new()
	_animator.name = "StateAnimator"
	_animator.animations = _mapa()
	_entidad.add_child(_animator)


## El diccionario va TIPADO o la asignación se rechaza en runtime: la propiedad
## es `Dictionary[int, StringName]` y un `Dictionary` pelado no encaja.
func _mapa() -> Dictionary[int, StringName]:
	var mapa: Dictionary[int, StringName] = {}
	mapa[GOLPEANDO] = &"enemy_strike"
	return mapa


## Con los nodos que `enemy_strike` nombra en sus pistas: `Attacker` para abrir y
## cerrar la ventana, y `Visuals/Hitbox` y `Visuals/Body` para el gesto. Sin
## ellos la animación se queja de pistas sin resolver, y GUT cuenta esos avisos
## del motor como fallos — con razón: una entidad a la que le faltan los nodos
## que su animación espera no representa a la que corre en el juego.
func _montar_entidad() -> Node2D:
	var raiz := Node2D.new()

	var machine := MachineScript.new() as StateMachine
	machine.name = "StateMachine"
	raiz.add_child(machine)

	var visuals := Node2D.new()
	visuals.name = "Visuals"
	raiz.add_child(visuals)

	var body := Polygon2D.new()
	body.name = "Body"
	visuals.add_child(body)

	var hitbox := HitboxScript.new() as Hitbox
	hitbox.name = "Hitbox"
	var forma := CollisionShape2D.new()
	forma.shape = RectangleShape2D.new()
	hitbox.add_child(forma)
	visuals.add_child(hitbox)

	var attacker := AttackerScript.new() as Attacker
	attacker.name = "Attacker"
	raiz.add_child(attacker)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", EnemyAnimations)
	raiz.add_child(player)
	return raiz


## --- El caso que motiva el nodo ---

func test_el_estado_que_llega_replicado_dispara_la_animacion() -> void:
	assert_false(_player.is_playing(), "de partida no anima nada")
	# Esto es literalmente lo que hace el `MultiplayerSynchronizer` al recibir.
	_machine.replicated_state = GOLPEANDO
	assert_true(_player.is_playing(), "el peer remoto tiene que ver el gesto")
	assert_eq(_player.current_animation, &"enemy_strike")


func test_un_estado_sin_animacion_no_rompe_nada() -> void:
	# Caminar y estar quieto no tienen animación mientras no haya arte.
	_machine.replicated_state = ANDANDO
	assert_false(_player.is_playing())
	_machine.replicated_state = QUIETO
	assert_false(_player.is_playing())


func test_no_reinicia_una_animacion_que_ya_esta_sonando() -> void:
	# En el peer que simula, el `Attacker` la lanza ANTES de que el estado cambie.
	# Volver a llamar a `play()` la rearrancaría desde cero y movería las pistas
	# que abren y cierran la ventana de daño.
	_player.play(&"enemy_strike")
	_player.seek(0.4, true)
	var antes := _player.current_animation_position

	_machine.replicated_state = GOLPEANDO
	assert_almost_eq(_player.current_animation_position, antes, 0.01,
			"la animación en curso no se toca")


func test_sin_state_machine_avisa_y_no_revienta() -> void:
	var suelto := Node2D.new()
	add_child_autofree(suelto)
	var huerfano := AnimatorScript.new()
	huerfano.animations = _mapa()
	suelto.add_child(huerfano)
	pass_test("montarlo sin máquina de estados no debe tumbar la escena")


## --- Y lo que el gesto replicado NO puede hacer ---

func test_el_gesto_replicado_no_abre_ventana_de_dano() -> void:
	# El corazón del asunto: las pistas de método de la animación llaman a
	# `Attacker.open_window()`, así que reproducir el gesto en el peer que no
	# simula abriría una ventana de daño real y el golpe se encaminaría DOS
	# veces. Lo impide `open_window()` ignorando a quien no empezó el ataque.
	var hitbox := _entidad.get_node("Visuals/Hitbox") as Hitbox
	var attacker := _entidad.get_node("Attacker") as Attacker
	await get_tree().process_frame

	assert_false(attacker.is_attacking(), "nadie ha empezado ningún golpe")
	attacker.open_window()
	assert_false(hitbox.is_active(),
			"un gesto que nadie empezó no puede abrir la ventana de daño")


## --- Y que el enemigo de verdad lo lleve puesto ---

func test_el_enemigo_monta_su_animador_con_el_mapeo_cargado() -> void:
	# Un `Dictionary[int, StringName]` escrito a mano en el `.tscn` se rechaza en
	# silencio si el tipo no encaja: el nodo se queda con el diccionario vacío,
	# el enemigo no anima en el peer remoto y todo lo demás sigue funcionando.
	# Exactamente la forma de fallo que este proyecto lleva ocho veces sufriendo.
	var enemigo := EnemyScene.instantiate()
	add_child_autofree(enemigo)
	var animador := enemigo.get_node_or_null("StateAnimator")
	assert_not_null(animador, "el enemigo tiene que montar su StateAnimator")
	assert_true(animador.animations.has(Enemy.State.ATTACK),
			"sin la entrada de ATTACK el gesto no llega al peer remoto")
	assert_eq(animador.animations[Enemy.State.ATTACK], &"enemy_strike")
