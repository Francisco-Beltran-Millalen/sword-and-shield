# Animación — estado y plan, para retomarlo de cero

**Estado: el jugador está animado y la suite está verde. El plan de abajo NO está
empezado.** Baseline: 21 scripts, 229 tests, 229 pasando (`eedb4de`).

No hay nada roto ni a medias. Lo que hay es un sistema que funciona y cuatro huecos
**medidos**, no intuidos. Cada fase de abajo lleva su medición de partida, su test y su
forma de verlo.

---

## Qué hay hoy

- `characters/player/player.tscn` — el cuerpo es un `Skeleton2D` con **11 `Bone2D`** y una
  primitiva rígida por hueso (círculos y cápsulas, sin pesos: cut-out, no skinning).
  Proporción 1:1 (cabeza 22 px, cuerpo 22 px), altura total 44 px.
- `characters/player/player_animations.tres` — 8 poses: `idle` `walk` `jump` `fall`
  `hurt` `downed` `attack` `guard`.
- `characters/player/player_pose_machine.tres` — `AnimationNodeStateMachine` con las 8
  poses y el grafo completo (56 aristas), `xfade` 0,12 uniforme.
- `components/state_animation_tree.gd` (118) — conduce el árbol. Escucha el `StateMachine`
  del anfitrión y una señal de pose opcional. **No conoce a `Player`, ni a los kits, ni a
  la red.**
- `tools/visual_bench/` — pilota a los dos jugadores por las poses sin teclado.
- `tests/integration/test_player_animation.gd` — 15 tests.

---

## Los cuatro huecos, medidos

Medido el 20 sep 2026 conduciendo a los jugadores del `_harness`, no deducido:

| Hueco | Medición | Se ve como |
| --- | --- | --- |
| **Andar con la guardia alta** | pose `guard`, recorrido del muslo **0,008 rad**; avanzó 49,5 px | El jugador del escudo **se desliza sin mover las piernas**. Es la mitad del reparto de kits |
| **El pie patina** | el pie apoyado se mueve hasta **4,62 px/frame en el MUNDO** (0 = plantado) | El ciclo suena a ritmo fijo y el cuerpo va a otra velocidad. Con guardia el cuerpo va al **45 %** (99 vs 220 px/s) y el desajuste se duplica |
| **No hay aterrizaje** | secuencia real de poses al saltar: `jump → fall → idle` | Se cae y se está de pie en un fundido de 0,12 s. El impacto no existe |
| **El enemigo no tiene cuerpo** | `enemy.tscn`: **0 `Bone2D`**, 0 `Skeleton2D` | Un rectángulo rojo de 44×44 al lado de dos muñecos articulados |

**Reproducir las mediciones:** las cuatro salen de una sonda temporal sobre
`tests/integration/_harness.gd` que lee `playback.get_current_node()`, la rotación de los
`Bone2D` y la posición en mundo del polígono del pie. No se dejó en el repo porque son
sondas, no asertos; las Fases 1 y 2 las convierten en tests de verdad.

---

## Qué NO re-litigar

Está decidido y medido; cambiarlo cuesta más que aceptarlo.

- **Cut-out, no skinning.** Con círculos y cuadrados el skinning sólo deforma. Los huesos
  ya están puestos para el día que haya arte con pesos.
- **Cadera y torso son huesos separados** aunque compartan origen. Es lo que permite que
  contra-roten, y eso es la transferencia de peso. Con un solo hueso de tronco el muñeco
  gira en bloque.
- **Dos segmentos por miembro** con su círculo de articulación. El círculo no es adorno:
  tapa el hueco que abre la junta al doblarse.
- **El `AnimationTree` corre en FÍSICA** (`callback_mode_process = 0`), no en el bucle de
  dibujo. El estado que elige la pose se decide en `_physics_process`, y en `--headless`
  el bucle de dibujo avanza con un delta minúsculo: un test que conduzca al jugador vería
  las poses cambiar y los huesos casi quietos.
- **El grafo se teje completo** (56 aristas) porque Godot 4 no tiene nodo "Any State",
  sólo `Start` y `End`. Sin aristas `travel()` no falla: teletransporta, y el cambio de
  pose se ve como un salto.
- **El brazo delantero se mueve poco a propósito** en todas las poses. Es consecuencia de
  la Fase 5, no pereza.

---

## Fase 0 — Recuperar el generador de animaciones *(bloquea todo lo demás)*

**El problema:** `player_animations.tres` (20 KB) y `player_pose_machine.tres` (15 KB) los
escribió un script `gen_anims.gd` que vivía en el directorio temporal de la sesión y **no
se versionó. Ya no existe.** Hoy, tocar una sola clave de una pose obliga a editar a mano
un `.tres` de 600 líneas de `PackedFloat32Array`, o a reescribir el generador.

**Qué hacer:** reconstruirlo en `tools/anim_gen/gen_player_anims.gd` y versionarlo. Es un
`SceneTree` que construye `Animation`, `AnimationLibrary` y `AnimationNodeStateMachine` con
la API y los guarda con `ResourceSaver` — se deja que el motor serialice, que es donde
uno se inventa formatos.

```bash
godot --headless --path . -s tools/anim_gen/gen_player_anims.gd
```

**Reconstruirlo desde el `.tres`, no desde cero:** las poses actuales están afinadas
contra mediciones (alturas de pierna cuadradas al milímetro, clave de despegue a 0,05 s).
Leer los valores del `.tres` existente y volcarlos al generador; luego regenerar y **exigir
que el `.tres` salga byte a byte igual** antes de tocar nada. Si no sale igual, el
generador aún no reproduce lo que hay.

**Trampas del generador, ya pagadas una vez:**

- **Signos.** Los huesos de los miembros apuntan a **+Y**, así que rotarlos en POSITIVO
  lleva la punta hacia **-X**: *adelante es NEGATIVO*. El tronco y la cabeza apuntan a -Y
  y van al revés. Esto ya costó un ciclo de andar entero (trampa nº10 de `AGENTS.md`).
- **Interpolación.** Cúbica para los gestos; **LINEAL en las pistas que sostienen el
  peso** (cadera y piernas). El cúbico sobrepasa entre claves y mete el pie bajo el suelo
  aunque todas las claves cuadren.
- **Con `-s`, en `_init()` todavía no hay autoloads.** El generador no debe nombrar
  ninguno ni cargar scripts que lo hagan.

---

## Fase 1 — Que el pie deje de patinar

**De 4,62 px/frame a ~0.** El ciclo `walk` suena siempre a la misma velocidad; el cuerpo
no. Se arregla escalando el tiempo de la animación con la velocidad real (§13: lo hace el
motor, no un contador propio).

**Verificado que existe en 4.7:** un `AnimationNodeBlendTree` **sí** puede ser un estado
del `AnimationNodeStateMachine`. Así que el estado `walk` pasa de ser un
`AnimationNodeAnimation` a un BlendTree con `Anim → TimeScale → output`, y queda un
parámetro escribible (confirmar su ruta exacta en ejecución; será del orden de
`parameters/walk/Escala/scale`).

**Quién lo escribe:** el propio `StateAnimationTree`, en `_physics_process`, leyendo
`velocity` del anfitrión. **Esto no viola §1 ni §5**: la constitución dice que un servicio
puede leer hechos de los nodos de su propia entidad — eso es autoconocimiento, no dato
entre sistemas. Comprobar `root is CharacterBody2D`, **nunca castear a `Player`**: así
sirve igual al enemigo de la Fase 4.

**Medir la longitud de paso, no deducirla.** La escala es
`velocidad_real / (longitud_de_paso · pasos_por_segundo)`. La longitud de paso se obtiene
conduciendo al jugador y midiendo cuánto recorre el pie apoyado respecto al cuerpo durante
su fase de apoyo. Tres diseños de escalera ya pasaron la aritmética y se atascaron al
pilotarlos; esto es lo mismo.

**Test que lo fija** — y es el que faltaba: el test actual
(`test_el_pie_apoyado_retrocede_respecto_al_cuerpo`) mide el pie **respecto al cuerpo**, y
por eso el patinaje pasó por delante de él. El nuevo mide el pie en **coordenadas de
mundo**: un pie plantado no se mueve. Tolerancia sugerida: < 1 px/frame, y verificar a las
dos velocidades (con guardia y sin ella), porque **un fallo que sólo aparece con dos no
aparece con uno**.

---

## Fase 2 — Andar con la guardia alta (y atacar andando)

**El fallo:** `Player.State.KIT_ACTION` es un estado único, y con la guardia levantada la
pose `guard` se adueña del cuerpo entero. Muslo: 0,008 rad mientras avanza 49,5 px.

**El arreglo de raíz es partir el cuerpo en dos capas**, que es como se resuelve esto en
cualquier motor: las piernas hacen locomoción y el tren superior hace lo del kit.
Verificado que las dos piezas existen en 4.7:

- `AnimationNodeBlend2` con `filter_enabled` y `set_filter_path()` por pista.
- `AnimationNodeStateMachine` **anidado** dentro de un `AnimationNodeBlendTree`
  (`state_machine_type = STATE_MACHINE_TYPE_GROUPED`).

**Forma propuesta:**

```
tree_root = AnimationNodeBlendTree
├── Piernas (StateMachine GROUPED)   idle · walk · jump · fall · land
├── Torso   (StateMachine GROUPED)   neutral · attack · guard · hurt
└── Blend2 filtrado                  las pistas del tren superior vienen de Torso
```

**Lo mejor de esta forma: `state_animation_tree.gd` no se toca.** Se cuelgan **DOS** nodos
del jugador, cada uno con su `playback_parameter` (`parameters/Piernas/playback` y
`parameters/Torso/playback`) y su propio mapa `animations`. El de piernas ignora
`KIT_ACTION`; el de torso es el que escucha `pose_changed`. El componente ya es
configurable por `@export` justamente para esto — si hace falta cambiarlo, parar y
replantear.

**Las poses hay que partirlas** (de ahí la Fase 0): `walk` deja de tocar torso y brazos;
`guard` deja de tocar cadera y piernas. Ojo con una consecuencia concreta: hoy `guard` se
agacha moviendo `Hip.position`, y la cadera pertenece a la capa de PIERNAS — el agacharse
hay que expresarlo con `Torso.position`, o la guardia dejará de agacharse.

**Decisión abierta, con recomendación:** `downed` afecta al cuerpo entero y no encaja en
ninguna capa. Recomendado: un `Blend2` extra en la raíz que mande una pose de cuerpo
completo al 100 % cuando el estado sea `DOWNED`. Alternativa más barata: duplicar `downed`
en las dos capas y aceptar la duplicación. Decidir al llegar, no antes.

**Test que lo fija:** andar con la guardia alta y exigir que el muslo recorra > 0,2 rad
**y** que la pose del torso sea `guard` a la vez. Hoy ese test falla con 0,008.

---

## Fase 3 — Aterrizaje

**Medido:** `jump → fall → idle`, sin nada en medio.

**El truco es puro motor y no toca ni una línea de GDScript:** añadir un nodo `land` a la
capa de piernas y **quitar las aristas directas** `fall → idle` y `fall → walk`, dejando
sólo `fall → land` y `land → {idle, walk}`. El pathfinding de `travel()` pasa entonces
obligatoriamente por `land`. La salida de `land` va con
`advance_mode = ADVANCE_MODE_AUTO` (verificado que existe) para que se encadene sola al
terminar.

**Verificar en ejecución** que `travel()` reproduce de verdad los nodos intermedios del
camino y no salta al destino. Si no lo hiciera, la alternativa es un estado `LAND`
transitorio en `Player.State` — más caro, porque engorda el orquestador.

---

## Fase 4 — El enemigo estrena el esqueleto

Hoy `enemy.tscn` tiene 0 huesos. **Y no debería estrenar nada**: ese es el principio del
proyecto — el enemigo usa `Locomotion`, `Attacker`, `Hitbox`, `Hurtbox`, `DamageReceiver`,
stats y salud del jugador sin una línea propia.

**Qué hacer:** extraer el esqueleto de `player.tscn` a una escena instanciable
(`characters/common/body_rig.tscn`) y colgarla bajo `Visuals` del enemigo, más un
`StateAnimationTree` con el mapa de `Enemy`. El color por rol sale por `modulate` del nodo
raíz del rig, no duplicando polígonos.

**La trampa nº7 acecha aquí y la documentación ya dice que estaba resuelta:**
`_apply_body_size` escribe las formas desde el arquetipo, y un rig con sub-recursos
compartidos entre instancias haría que el último enemigo en entrar al árbol le impusiera
su cuerpo a todos. `resource_local_to_scene` en todo lo que sea recurso. **El test que
sirve monta DOS enemigos con arquetipos distintos** — con uno solo el código está bien.

Segunda trampa: el arquetipo escala el cuerpo (44 px hoy), y el rig está dibujado para 44
de alto. O el rig se escala con el arquetipo, o un enemigo grande saldrá con un cuerpo de
120 y un dibujo de 44 — que es literalmente lo que ya pasó una vez.

---

## Fase 5 — El kit cuelga de la mano *(la más invasiva; hacerla la última)*

Ya está en `ARCHITECTURE-MAP.md` → *Deferred* con su disparador. Hoy la empuñadura está
clavada en (14,-12) y por eso **el brazo delantero se anima poco en todas las poses**:
uno expresivo dejaría la espada flotando lejos de la mano.

Colgarlo de `ForearmFront` lo arregla y de paso hace que la hitbox siga al arma, que es
más correcto. Lo que cuesta: toca `equip_kit`, **el volteo se aplicaría dos veces**
(`_apply_facing_visuals` escribe `kit.scale.x` y el kit heredaría el de `Visuals`), y la
`GuardBox` pasaría a girar con el hombro. No empezarla sin cerrar esas tres.

---

## Cómo verificar cualquiera de las fases

**La suite no basta y aquí está probado:** el muñeco caminó de espaldas con quince tests
en verde, porque todos medían que las cosas SE MUEVEN y ninguno hacia dónde.

```bash
# 1. La suite, mirando el conteo de Scripts y no el mensaje final
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# 2. Verlo: una tira de fotogramas del ciclo
godot --path . --scene res://tools/visual_bench/visual_bench.tscn \
      --write-movie /tmp/b/f.png --fixed-fps 30 --quit-after 270
ls /tmp/b | wc -l          # el conteo de archivos es la señal, no el mensaje
magick /tmp/b/f0000008{4,7}.png /tmp/b/f000000{90,93,96,99}.png +append /tmp/tira.png

# 3. El juego de verdad, que es el único caso que representa al juego
godot --path . --write-movie /tmp/h/f.png --fixed-fps 30 --quit-after 300 -- --host &
sleep 4
godot --path . --write-movie /tmp/c/f.png --fixed-fps 30 --quit-after 240 -- --join 127.0.0.1 &
```

**Añadir al `visual_bench` un tramo de andar CON la guardia alta** al empezar la Fase 2:
hoy el guion no lo cubre, y es justamente el caso roto.

**Y en el mismo commit que el código:** `docs/adr/ARCHITECTURE-MAP.md`.
`tests/unit/test_architecture_map.gd` falla en rojo si el mapa miente, si una clase nueva
no está registrada o si alguien pasa de 400 líneas (§6).
