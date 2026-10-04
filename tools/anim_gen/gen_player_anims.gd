extends SceneTree

## Regenera `player_animations.tres` y `player_pose_machine.tres`.
##
## Los dos `.tres` los escribió un `gen_anims.gd` que no se versionó y se perdió.
## Sin esto, tocar una clave de una pose obliga a editar a mano un `.tres` de
## cientos de líneas de `PackedFloat32Array`. Este script reconstruye el
## generador con la API pública de `Animation`, `AnimationLibrary` y
## `AnimationNodeStateMachine` y deja que `ResourceSaver` serialice (§13).
##
## Los valores están copiados del `.tres` existente y afinados contra mediciones
## (alturas de pierna al milímetro, clave de despegue a 0,05 s). Regenerar debe
## devolver un recurso IDÉNTICO EN CONTENIDO al actual: `length`, `loop_mode` y
## cada pista (path, interp, times, values), y la máquina con sus 8 estados y 56
## aristas. Los ids de los sub-recursos cambian en cada guardado; eso no cuenta.
##
##     godot --headless --path . -s tools/anim_gen/gen_player_anims.gd
##
## Con `-s` el script ES el MainLoop: `_init()` corre antes de que exista el
## main loop, así que se espera un frame igual que hace GUT. No nombra autoloads.

const ANIM_PATH := "res://characters/player/player_animations.tres"
const MACHINE_PATH := "res://characters/player/player_pose_machine.tres"
const STEP := 0.02

const LINEAR := Animation.INTERPOLATION_LINEAR
const CUBIC := Animation.INTERPOLATION_CUBIC
const LOOP_NONE := Animation.LOOP_NONE
const LOOP_LINEAR := Animation.LOOP_LINEAR

const HIP_POS := "Skeleton/Hip:position"
const HIP_ROT := "Skeleton/Hip:rotation"
const TORSO_POS := "Skeleton/Hip/Torso:position"
const TORSO_ROT := "Skeleton/Hip/Torso:rotation"
const HEAD := "Skeleton/Hip/Torso/Head:rotation"
const ARM_F := "Skeleton/Hip/Torso/ArmFront:rotation"
const FOREARM_F := "Skeleton/Hip/Torso/ArmFront/ForearmFront:rotation"
const ARM_B := "Skeleton/Hip/Torso/ArmBack:rotation"
const FOREARM_B := "Skeleton/Hip/Torso/ArmBack/ForearmBack:rotation"
const LEG_F := "Skeleton/Hip/LegFront:rotation"
const SHIN_F := "Skeleton/Hip/LegFront/ShinFront:rotation"
const LEG_B := "Skeleton/Hip/LegBack:rotation"
const SHIN_B := "Skeleton/Hip/LegBack/ShinBack:rotation"

## Pistas de la capa de PIERNAS (locomoción): cadera y piernas.
const LEGS_PATHS: Array[String] = [HIP_POS, HIP_ROT, LEG_F, SHIN_F, LEG_B, SHIN_B]
## Pistas de la capa de TORSO (kit): tronco, cabeza y brazos.
const TORSO_PATHS: Array[String] = [TORSO_POS, TORSO_ROT, HEAD, ARM_F, FOREARM_F, ARM_B, FOREARM_B]


func _init() -> void:
	var iter := 0
	while Engine.get_main_loop() == null and iter < 20:
		await create_timer(0.01).timeout
		iter += 1
	_generar()
	quit()


func _generar() -> void:
	# Cada pose original se PARTE en dos: las pistas de cadera/piernas van a la
	# capa de locomoción y las de tronco/brazos a la capa del kit. Así un kit no
	# congela las piernas (Fase 2). `neutral_torso` sale de la pose `idle`.
	var poses := {}
	for pose in _poses():
		poses[pose.name] = pose.anim

	var lib := AnimationLibrary.new()
	for split in _splits():
		var origen: Animation = poses[split["from"]]
		lib.add_animation(split["name"], _split(origen, split["legs"]))
	# El aterrizaje no sale de ninguna pose: es un gesto propio de las piernas.
	lib.add_animation(&"land_legs", _land_legs())
	# La guardia se agachaba moviendo `Hip:position` (hoy de la capa de piernas):
	# el agacharse se expresa con `Torso:position`, o la guardia deja de agacharse.
	_anadir_agacharse(lib.get_animation(&"guard_torso"))

	var err := ResourceSaver.save(lib, ANIM_PATH)
	if err != OK:
		push_error("No se pudo guardar %s" % ANIM_PATH)

	var arbol := _montar_arbol()
	err = ResourceSaver.save(arbol, MACHINE_PATH)
	if err != OK:
		push_error("No se pudo guardar %s" % MACHINE_PATH)


## Qué se parte y con qué nombre queda en la biblioteca. Las poses de kit
## (attack, guard, hurt) sólo dejan su mitad de torso; la de piernas de esas
## poses no se usa — durante el ataque o la guardia las piernas andan o esperan.
func _splits() -> Array:
	return [
		{"name": &"idle_legs", "from": &"idle", "legs": true},
		{"name": &"neutral_torso", "from": &"idle", "legs": false},
		{"name": &"walk_legs", "from": &"walk", "legs": true},
		{"name": &"jump_legs", "from": &"jump", "legs": true},
		{"name": &"fall_legs", "from": &"fall", "legs": true},
		{"name": &"downed_legs", "from": &"downed", "legs": true},
		{"name": &"attack_torso", "from": &"attack", "legs": false},
		{"name": &"guard_torso", "from": &"guard", "legs": false},
		{"name": &"hurt_torso", "from": &"hurt", "legs": false},
		{"name": &"downed_torso", "from": &"downed", "legs": false},
	]


## ---------------------------------------------------------------- poses

func _poses() -> Array:
	return [
		{"name": &"attack", "anim": _anim(0.32, LOOP_NONE, [
			_trk(HIP_POS, CUBIC, [0.0, 0.1, 0.2, 0.32], [_v(0.0, -11.0), _v(-2.0, -10.2), _v(2.5, -10.6), _v(0.0, -11.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.0, -0.14, 0.2, 0.0]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.0, -0.2, 0.3, 0.0]),
			_trk(HEAD, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.0, 0.22, -0.28, 0.0]),
			_trk(ARM_F, CUBIC, [0.0, 0.1, 0.2, 0.32], [-0.3, -0.08, -0.58, -0.3]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.1, 0.2, 0.32], [-0.85, -1.0, -0.68, -0.85]),
			_trk(ARM_B, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.12, -0.8, 0.65, 0.12]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.1, 0.2, 0.32], [-0.22, -0.6, -0.2, -0.22]),
			_trk(LEG_F, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.04, 0.28, -0.45, 0.04]),
			_trk(SHIN_F, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.05, 0.1, 0.3, 0.05]),
			_trk(LEG_B, CUBIC, [0.0, 0.1, 0.2, 0.32], [-0.03, -0.25, 0.4, -0.03]),
			_trk(SHIN_B, CUBIC, [0.0, 0.1, 0.2, 0.32], [0.11, 0.55, 0.05, 0.11]),
		])},
		{"name": &"downed", "anim": _anim(0.5, LOOP_NONE, [
			_trk(HIP_POS, CUBIC, [0.0, 0.22, 0.5], [_v(0.0, -11.0), _v(-3.0, -5.0), _v(-8.0, -3.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.22, 0.5], [0.0, -0.5, -1.5708]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.22, 0.5], [0.0, 0.25, 0.35]),
			_trk(HEAD, CUBIC, [0.0, 0.22, 0.5], [0.0, 0.2, 0.4]),
			_trk(ARM_F, CUBIC, [0.0, 0.22, 0.5], [-0.3, 0.55, 0.95]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.22, 0.5], [-0.85, -0.55, -0.4]),
			_trk(ARM_B, CUBIC, [0.0, 0.22, 0.5], [0.12, 0.6, 1.1]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.22, 0.5], [-0.22, -0.35, -0.45]),
			_trk(LEG_F, CUBIC, [0.0, 0.22, 0.5], [0.04, -0.75, -1.05]),
			_trk(SHIN_F, CUBIC, [0.0, 0.22, 0.5], [0.05, 0.95, 1.35]),
			_trk(LEG_B, CUBIC, [0.0, 0.22, 0.5], [-0.03, -0.45, -0.65]),
			_trk(SHIN_B, CUBIC, [0.0, 0.22, 0.5], [0.11, 0.85, 1.15]),
		])},
		{"name": &"fall", "anim": _anim(0.8, LOOP_LINEAR, [
			_trk(HIP_POS, CUBIC, [0.0, 0.4, 0.8], [_v(0.0, -11.0), _v(0.0, -10.3), _v(0.0, -11.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.4, 0.8], [-0.05, -0.09, -0.05]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.4, 0.8], [0.12, 0.17, 0.12]),
			_trk(HEAD, CUBIC, [0.0, 0.4, 0.8], [-0.12, -0.16, -0.12]),
			_trk(ARM_F, CUBIC, [0.0, 0.4, 0.8], [-0.55, -0.72, -0.55]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.4, 0.8], [-1.0, -1.15, -1.0]),
			_trk(ARM_B, CUBIC, [0.0, 0.4, 0.8], [1.95, 2.2, 1.95]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.4, 0.8], [-0.3, -0.5, -0.3]),
			_trk(LEG_F, CUBIC, [0.0, 0.4, 0.8], [-0.5, -0.35, -0.5]),
			_trk(SHIN_F, CUBIC, [0.0, 0.4, 0.8], [0.2, 0.35, 0.2]),
			_trk(LEG_B, CUBIC, [0.0, 0.4, 0.8], [0.4, 0.25, 0.4]),
			_trk(SHIN_B, CUBIC, [0.0, 0.4, 0.8], [0.55, 0.7, 0.55]),
		])},
		{"name": &"guard", "anim": _anim(1.2, LOOP_LINEAR, [
			_trk(HIP_POS, CUBIC, [0.0, 0.6, 1.2], [_v(-1.0, -10.0), _v(-1.0, -9.4), _v(-1.0, -10.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.6, 1.2], [-0.06, -0.08, -0.06]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.6, 1.2], [0.22, 0.26, 0.22]),
			_trk(HEAD, CUBIC, [0.0, 0.6, 1.2], [-0.24, -0.27, -0.24]),
			_trk(ARM_F, CUBIC, [0.0, 0.6, 1.2], [-1.05, -1.0, -1.05]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.6, 1.2], [-0.85, -0.9, -0.85]),
			_trk(ARM_B, CUBIC, [0.0, 0.6, 1.2], [0.4, 0.36, 0.4]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.6, 1.2], [-0.55, -0.5, -0.55]),
			_trk(LEG_F, CUBIC, [0.0, 0.6, 1.2], [-0.6, -0.62, -0.6]),
			_trk(SHIN_F, CUBIC, [0.0, 0.6, 1.2], [0.62, 0.64, 0.62]),
			_trk(LEG_B, CUBIC, [0.0, 0.6, 1.2], [0.35, 0.33, 0.35]),
			_trk(SHIN_B, CUBIC, [0.0, 0.6, 1.2], [0.1, 0.12, 0.1]),
		])},
		{"name": &"hurt", "anim": _anim(0.34, LOOP_NONE, [
			_trk(HIP_POS, CUBIC, [0.0, 0.1, 0.34], [_v(0.0, -11.0), _v(-2.5, -9.8), _v(0.0, -11.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.1, 0.34], [0.0, 0.22, 0.0]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.1, 0.34], [0.0, -0.55, 0.0]),
			_trk(HEAD, CUBIC, [0.0, 0.1, 0.34], [0.0, -0.42, 0.0]),
			_trk(ARM_F, CUBIC, [0.0, 0.1, 0.34], [-0.3, 0.35, -0.3]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.1, 0.34], [-0.85, -0.35, -0.85]),
			_trk(ARM_B, CUBIC, [0.0, 0.1, 0.34], [0.12, 1.45, 0.12]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.1, 0.34], [-0.22, -0.3, -0.22]),
			_trk(LEG_F, CUBIC, [0.0, 0.1, 0.34], [0.04, -0.55, 0.04]),
			_trk(SHIN_F, CUBIC, [0.0, 0.1, 0.34], [0.05, 0.35, 0.05]),
			_trk(LEG_B, CUBIC, [0.0, 0.1, 0.34], [-0.03, 0.45, -0.03]),
			_trk(SHIN_B, CUBIC, [0.0, 0.1, 0.34], [0.11, 0.7, 0.11]),
		])},
		{"name": &"idle", "anim": _anim(3.2, LOOP_LINEAR, [
			_trk(HIP_POS, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [_v(-0.7, -11.0), _v(-0.7, -11.0), _v(0.7, -11.0), _v(0.7, -11.0), _v(-0.7, -11.0)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.05, 0.05, -0.05, -0.05, 0.05]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [-0.06, -0.03, 0.06, 0.03, -0.06]),
			_trk(TORSO_POS, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [_v(0.0, 0.0), _v(0.0, -0.7), _v(0.0, 0.0), _v(0.0, -0.7), _v(0.0, 0.0)]),
			_trk(HEAD, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.03, -0.02, -0.03, 0.02, 0.03]),
			_trk(ARM_B, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.12, 0.04, -0.06, 0.02, 0.12]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [-0.22, -0.32, -0.14, -0.26, -0.22]),
			_trk(ARM_F, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [-0.3, -0.27, -0.33, -0.3, -0.3]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [-0.85, -0.89, -0.82, -0.87, -0.85]),
			_trk(LEG_B, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [-0.03, -0.03, 0.04, 0.04, -0.03]),
			_trk(SHIN_B, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.11, 0.11, 0.05, 0.05, 0.11]),
			_trk(LEG_F, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.04, 0.04, -0.03, -0.03, 0.04]),
			_trk(SHIN_F, CUBIC, [0.0, 0.8, 1.6, 2.4, 3.2], [0.05, 0.05, 0.11, 0.11, 0.05]),
		])},
		{"name": &"jump", "anim": _anim(0.4, LOOP_NONE, [
			_trk(HIP_POS, CUBIC, [0.0, 0.4], [_v(0.0, -9.8), _v(0.0, -12.2)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.4], [0.06, 0.02]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.4], [-0.16, -0.1]),
			_trk(HEAD, CUBIC, [0.0, 0.4], [0.08, 0.05]),
			_trk(ARM_F, CUBIC, [0.0, 0.4], [-0.5, -0.8]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.4], [-0.95, -1.1]),
			_trk(ARM_B, CUBIC, [0.0, 0.4], [1.5, 2.1]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.4], [-0.45, -0.1]),
			_trk(LEG_F, CUBIC, [0.0, 0.4], [-0.6, -0.3]),
			_trk(SHIN_F, CUBIC, [0.0, 0.4], [0.9, 0.55]),
			_trk(LEG_B, CUBIC, [0.0, 0.4], [0.45, 0.25]),
			_trk(SHIN_B, CUBIC, [0.0, 0.4], [0.3, 0.2]),
		])},
		{"name": &"walk", "anim": _anim(0.6, LOOP_LINEAR, [
			_trk(HIP_POS, LINEAR, [0.0, 0.15, 0.3, 0.45, 0.6], [_v(0.8, -9.45), _v(0.0, -11.0), _v(-0.8, -9.45), _v(0.0, -11.0), _v(0.8, -9.45)]),
			_trk(HIP_ROT, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [0.08, 0.0, -0.08, 0.0, 0.08]),
			_trk(TORSO_ROT, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [0.02, 0.1, 0.18, 0.1, 0.02]),
			_trk(TORSO_POS, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [_v(0.0, 0.5), _v(0.0, 0.0), _v(0.0, 0.5), _v(0.0, 0.0), _v(0.0, 0.5)]),
			_trk(HEAD, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [-0.06, -0.12, -0.2, -0.12, -0.06]),
			_trk(LEG_F, LINEAR, [0.0, 0.15, 0.3, 0.35, 0.45, 0.6], [-0.55, -0.03, 0.5, 0.45, -0.2, -0.55]),
			_trk(SHIN_F, LINEAR, [0.0, 0.15, 0.3, 0.35, 0.45, 0.6], [0.05, 0.05, 0.1, 0.55, 0.9, 0.05]),
			_trk(LEG_B, LINEAR, [0.0, 0.05, 0.15, 0.3, 0.45, 0.6], [0.5, 0.45, -0.2, -0.55, -0.03, 0.5]),
			_trk(SHIN_B, LINEAR, [0.0, 0.05, 0.15, 0.3, 0.45, 0.6], [0.1, 0.55, 0.9, 0.05, 0.05, 0.1]),
			_trk(ARM_F, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [-0.3, -0.26, -0.34, -0.24, -0.3]),
			_trk(FOREARM_F, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [-0.85, -0.88, -0.8, -0.9, -0.85]),
			_trk(ARM_B, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [-0.55, 0.0, 0.55, 0.05, -0.55]),
			_trk(FOREARM_B, CUBIC, [0.0, 0.15, 0.3, 0.45, 0.6], [-0.7, -0.4, -0.15, -0.45, -0.7]),
		])},
	]


## ---------------------------------------------------------------- árbol

func _montar_arbol() -> AnimationNodeBlendTree:
	# Raíz: un BlendTree con DOS state machines anidadas (piernas y torso) y un
	# `Blend2` que las superpone por pista. Las pistas de torso van filtradas: el
	# `Blend2` con `filter_enabled` las toma SIEMPRE de la entrada 1 (Torso) a
	# `blend = 1`, y las de piernas (sin filtrar) pasan de la entrada 0 (Piernas).
	var raiz := AnimationNodeBlendTree.new()

	var piernas := _state_machine([
		[&"idle", &"idle_legs"], [&"land", &"land_legs"], [&"walk", &"walk_legs"],
		[&"jump", &"jump_legs"], [&"fall", &"fall_legs"], [&"downed", &"downed_legs"],
	], &"walk", &"idle",
		# Sin aristas directas `fall → idle` ni `fall → walk`: el pathfinding de
		# `travel()` pasa obligatoriamente por `land`. Las salidas de `land` se
		# auto-encadenan (AUTO) y la entrada a `land` funde al mínimo.
		[[&"fall", &"idle"], [&"fall", &"walk"]],
		[[&"land", &"idle"], [&"land", &"walk"]],
		[[&"fall", &"land"]])
	raiz.add_node(&"Piernas", piernas, Vector2(-400, 0))

	# Los nombres de NODO coinciden con lo que el kit anuncia (`pose_changed`
	# emite "attack" / "guard") y con los estados (`hurt`, `downed`). Los nombres
	# de ANIMACIÓN llevan sufijo para no chocar en la biblioteca compartida.
	var torso := _state_machine([
		[&"neutral", &"neutral_torso"], [&"attack", &"attack_torso"], [&"guard", &"guard_torso"],
		[&"hurt", &"hurt_torso"], [&"downed", &"downed_torso"],
	], &"", &"neutral")
	raiz.add_node(&"Torso", torso, Vector2(0, 200))

	var mezcla := AnimationNodeBlend2.new()
	mezcla.filter_enabled = true
	for path in TORSO_PATHS:
		mezcla.set_filter_path(NodePath(path), true)
	raiz.add_node(&"Mezcla", mezcla, Vector2(0, 0))
	raiz.connect_node(&"Mezcla", 0, &"Piernas")
	raiz.connect_node(&"Mezcla", 1, &"Torso")
	raiz.connect_node(&"output", 0, &"Mezcla")
	return raiz


## Una state machine anidada (`NESTED`) con grafo completo entre sus poses.
## Cada par es `[nombre_de_nodo, nombre_de_animación]`. Si `pose_escalable` no es
## vacío, ese nodo es un BlendTree con `TimeScale` (parámetro
## `parameters/<máquina>/<nodo>/Escala/scale`). La arista `Start` apunta a
## `pose_inicial` (nombre de nodo). `podadas` son aristas que no se crean;
## `auto_salidas` son aristas cuyo `advance_mode` es AUTO; `xfade_cero` son
## aristas que funden al mínimo en vez del 0,12 uniforme.
func _state_machine(pares: Array, pose_escalable: StringName, pose_inicial: StringName,
		podadas: Array = [], auto_salidas: Array = [], xfade_cero: Array = []) -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	machine.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
	var nombres: Array[StringName] = []
	var i := 0
	for par: Array in pares:
		var nombre: StringName = par[0]
		var animacion: StringName = par[1]
		nombres.append(nombre)
		var nodo: AnimationNode
		if nombre == pose_escalable:
			nodo = _walk_state(animacion)
		else:
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = animacion
			nodo = anim_node
		machine.add_node(nombre, nodo, Vector2(200 + i * 220, 120))
		i += 1

	# Grafo completo: sin arista `travel()` teletransporta. xfade uniforme 0,12.
	for desde: StringName in nombres:
		for hacia: StringName in nombres:
			if desde == hacia:
				continue
			if _es_arista(podadas, desde, hacia):
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = 0.0 if _es_arista(xfade_cero, desde, hacia) else 0.12
			tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
			# `ENABLED` para que `travel()` sí pueda cruzar la arista: con `DISABLED`
			# el A* de `travel()` la descarta y teletransporta al destino (sin
			# fundido). `AUTO` sólo en las salidas de `land`, que se encadenan solas.
			tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO \
					if _es_arista(auto_salidas, desde, hacia) \
					else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			machine.add_transition(desde, hacia, tr)

	var inicio := AnimationNodeStateMachineTransition.new()
	inicio.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
	inicio.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	machine.add_transition(&"Start", pose_inicial, inicio)
	return machine


func _es_arista(lista: Array, desde: StringName, hacia: StringName) -> bool:
	for arista: Array in lista:
		if arista[0] == desde and arista[1] == hacia:
			return true
	return false


## ---------------------------------------------------------------- helpers

## El aterrizaje: un golpe corto de las piernas (la cadera baja y rebota, las
## rodillas se doblan) para que la caída no funda en seco a `idle`.
func _land_legs() -> Animation:
	return _anim(0.12, LOOP_NONE, [
		_trk(HIP_POS, LINEAR, [0.0, 0.06, 0.12], [_v(0.0, -11.0), _v(0.0, -9.5), _v(0.0, -11.0)]),
		_trk(SHIN_F, LINEAR, [0.0, 0.06, 0.12], [0.05, 0.4, 0.05]),
		_trk(SHIN_B, LINEAR, [0.0, 0.06, 0.12], [0.11, 0.3, 0.11]),
	])


func _walk_state(pose: StringName) -> AnimationNodeBlendTree:
	var arbol := AnimationNodeBlendTree.new()
	var anim := AnimationNodeAnimation.new()
	anim.animation = pose
	arbol.add_node(&"Anim", anim)
	var escala := AnimationNodeTimeScale.new()
	arbol.add_node(&"Escala", escala)
	# `connect_node(destino, índice, origen)`: la entrada `índice` de `destino`
	# recibe la salida de `origen`. El nodo de salida del BlendTree es `output`.
	arbol.connect_node(&"Escala", 0, &"Anim")
	arbol.connect_node(&"output", 0, &"Escala")
	return arbol


## Una animación con sólo las pistas de piernas o de torso.
func _split(anim: Animation, piernas: bool) -> Animation:
	var keep: Array[String] = LEGS_PATHS if piernas else TORSO_PATHS
	var out := Animation.new()
	out.length = anim.length
	out.step = anim.step
	out.loop_mode = anim.loop_mode
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		if path in keep:
			var idx := out.add_track(Animation.TYPE_VALUE)
			out.track_set_path(idx, anim.track_get_path(i))
			out.track_set_interpolation_type(idx, anim.track_get_interpolation_type(i))
			for k in anim.track_get_key_count(i):
				out.track_insert_key(idx, anim.track_get_key_time(i, k), anim.track_get_key_value(i, k))
	return out


## La guardia se agachaba con `Hip:position`; reexpresada como `Torso:position`
## (la cadera ahora es de la capa de piernas, y durante la guardia esas piernas
## andan). Mismo recorrido que el `Hip:position` original, en coordenadas del
## tronco (resto (0,0)).
func _anadir_agacharse(anim: Animation) -> void:
	var idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(idx, NodePath(TORSO_POS))
	anim.track_set_interpolation_type(idx, CUBIC)
	for i in [0.0, 0.6, 1.2]:
		anim.track_insert_key(idx, i, _v(-1.0, 1.0) if i != 0.6 else _v(-1.0, 1.6))


func _trk(path: String, interp: int, times: Array, values: Array) -> Dictionary:
	return {"path": path, "interp": interp, "times": times, "values": values}


func _anim(length: float, loop: int, tracks: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.step = STEP
	anim.loop_mode = loop
	for track: Dictionary in tracks:
		var idx := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(idx, NodePath(track["path"]))
		anim.track_set_interpolation_type(idx, track["interp"])
		for k in track["times"].size():
			anim.track_insert_key(idx, track["times"][k], track["values"][k])
	return anim


func _v(x: float, y: float) -> Vector2:
	return Vector2(x, y)
