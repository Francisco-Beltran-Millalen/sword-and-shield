# Animación — estado y plan, para retomarlo de cero

**Estado: Fases 0 a 4 ejecutadas, suite en verde (21 scripts, 233 tests). Queda la
Fase 5** —el kit cuelga de la mano—, que es la más invasiva: toca `equip_kit`, el volteo
y la `GuardBox`. Las fases hechas dejaron hallazgos medidos anotados abajo (NESTED y no
GROUPED, `ADVANCE_MODE_ENABLED` y no DISABLED, el `land` como fundido de salida).

Lo que hay hoy es un sistema que funciona, con los cuatro huecos originales cerrados o
resueltos por el camino. Cada fase de abajo lleva su medición de partida, su test y su
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
que el `.tres` regenerado sea idéntico en contenido al actual**, comparando el recurso
cargado y no los bytes: los sub-recursos llevan ids que `ResourceSaver` genera al guardar
(`Animation_jafpu`, `AnimationNodeAnimation_fgkm7`, …) y saldrán distintos en cada guardado
aunque el contenido sea el mismo, así que "byte a byte" es un criterio que ningún
generador puede cumplir. La comparación es, por animación, `length`, `loop_mode` y cada
pista (path, interp, times, values); y por la máquina, estados y aristas (56). Si no sale
igual, el generador aún no reproduce lo que hay.

Medido el 20 sep 2026, porque la diferencia importa: cargar el `.tres` y volver a
guardarlo SÍ da bytes idénticos —los ids vienen del archivo y se reutilizan—, pero
construir el mismo recurso dos veces desde cero da `Animation_umtyf` y `Animation_mv3l7`.
Es decir: el criterio sólo falla en el caso que nos ocupa, que es justo el del generador.
Para un primer vistazo rápido sirve neutralizar los ids antes de comparar
(`sed -E 's/_[a-z0-9]{5}"/_X"/g'`); la comparación pista a pista sigue haciendo falta al
final, porque esa además detecta una reordenación que el diff textual deja pasar.

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

**Revisado al ejecutarlo — el objetivo "a ~0" era imposible.** Plantar el pie a 220 px/s
con piernas de 11 px exige ~8× de escala (~27 pasos/s) y las piernas parpadean como un
seizure. El arreglo final **acota** la escala con `max_walk_scale = 2,0` (`state_animation_tree.gd`):
cadencia natural (~6,7 pasos/s) y patinaje de ~2,8 px/frame — mejor que los 4,62 de
partida sin el parpadeo. Es el compromiso estándar de los metroidvania; plantar el pie de
verdad exige bajar la velocidad de marcha (220 → ~100) y retocar la geometría
(`OPENING_WIDTH` salta con carrerilla).

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
- `AnimationNodeStateMachine` **anidado** dentro de un `AnimationNodeBlendTree`.
  OJO, medido al ejecutarlo: el tipo correcto es `STATE_MACHINE_TYPE_NESTED`, **no
  `GROUPED`**. Con `GROUPED` el playback se marca `is_grouped` y sus `travel()` /
  `start()` fallan con `Condition "is_grouped" is true` — un playback agrupado lo
  conduce su máquina de estados PADRE, que aquí no existe porque la raíz es un
  `BlendTree`. `NESTED` deja `travel()`/`start()` libres y la capa es controlable
  desde `parameters/Piernas/playback` y `parameters/Torso/playback`. También se
  midió: el parámetro del `Blend2` se llama `blend_amount` (no `blend`), y es
  `StateAnimationTree` quien lo fija a 1 cada frame — no se serializa en el `.tres`.

**Forma propuesta:**

```
tree_root = AnimationNodeBlendTree
├── Piernas (StateMachine GROUPED)   idle · walk · jump · fall · land
├── Torso   (StateMachine GROUPED)   neutral · attack · guard · hurt
└── Blend2 filtrado                  las pistas del tren superior vienen de Torso
```

**Cómo se monta: DOS nodos, y `state_animation_tree.gd` SÍ se toca** (el "no se toca" de la
versión anterior era un error). Se cuelgan **DOS** nodos del jugador, cada uno con su
`playback_parameter` (`parameters/Piernas/playback` y `parameters/Torso/playback`) y su
propio mapa `animations`. El de torso es el que escucha `pose_changed`. El de piernas
escucha el estado, pero **el estado no basta durante `KIT_ACTION`**: guardando, el escudo
deja `_busy = true` de forma sostenida y `_settle_state` mete `KIT_ACTION` aunque se esté
andando, así que un mapa de estados que "ignore `KIT_ACTION`" deja las piernas congeladas
en la última pose — el mismo deslizamiento, en otra capa.

La capa de piernas necesita su propia noción de "¿ando?", y esa sólo sale de `velocity`
(comprobar `root is CharacterBody2D`, nunca castear a `Player`): con `KIT_ACTION` y
`|velocity.x| > umbral` elige `walk`, si no `idle`. Es la MISMA lectura de velocidad que
introduce la Fase 1, así que la Fase 2 depende de ella y no es un cambio sólo de datos:
hay que añadir al componente un override por velocidad análogo al `_pose` que hoy existe
para la señal. No se puede mapear `KIT_ACTION → walk` a pelo: un ataque quieto haría correr
las piernas. Las dos fases, bien encajadas, se refuerzan — la escala por velocidad de la
Fase 1 aplicada a un `walk` disparado por velocidad resuelve a la vez el patinaje y el
desajuste del 45 % de la guardia. `StateAnimationTree` sigue sin conocer a `Player` ni a
los kits: lee hechos de su propia entidad, que es autoconocimiento (§5).

**Alternativa considerada y descartada**, anotada para que no se re-litigue: arreglar el
ESTADO en vez de la animación, haciendo que el `Player` no entre en `KIT_ACTION` mientras
la guardia esté alta y se esté andando. Es tentador —`KIT_ACTION` significa "el kit se
adueñó del control" y guardando el jugador sí se mueve, al 45 %—, pero `replicated_state`
viaja por red y lo consumen el HUD y el `StateAnimator` del enemigo: cambiar qué significa
un estado es más caro que añadir una lectura de velocidad, y se paga en sitios que no se
ven desde aquí.

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
terminar. Ojo con el `xfade_time` de las aristas hacia `land`: un fundido de 0,12 s se
come un aterrizaje corto — las entradas a `land` van con fundido mínimo, o el impacto
vuelve a no leerse.

**Verificar en ejecución** que `travel()` reproduce de verdad los nodos intermedios del
camino y no salta al destino. Si no lo hiciera, la alternativa es un estado `LAND`
transitorio en `Player.State` — más caro, porque engorda el orquestador.

**Tres hallazgos medidos al ejecutarlo**, que el plan de arriba no anticipaba:

1. **Las aristas normales van con `ADVANCE_MODE_ENABLED`, no `DISABLED`.** El A* de
   `travel()` descarta las aristas `DISABLED` (`_make_travel_path` hace `continue`), así
   que con `DISABLED` **teletransporta** al destino: ni fundido ni nodos intermedios. Es
   un fallo latente que arrastraba el `.tres` original —el "xfade 0,12" nunca se aplicó—.
   `AUTO` queda sólo para las salidas de `land`.
2. **El A* decide por POSICIONES de los nodos** (distancia 2D × prioridad), no por
   semántica. Con los nodos en línea, `fall → jump → idle` es geométricamente más corto
   que `fall → land → idle` y el aterrizaje se colaba por `jump`. Se arregla **colocando
   `land` entre `idle` y `walk`** en el layout (`idle · land · walk · jump · fall ·
   downed`), no con más poda — `fall → jump` hace falta para el doble salto.
3. **`land` se reproduce como fundido de salida, no como nodo actual.** `travel()` entra
   en `land` con xfade 0 y al frame siguiente ya está fundiendo `land → idle` (0,12 s),
   así que `get_current_node()` devuelve `idle` y `land` está en `get_fading_from_node()`.
   El test lo caza por `fading_from`, no por la pose actual.

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

Tercera trampa: la ventana de daño del golpe enemigo vive en `enemy_animations.tres` como
pistas **method** (`open_window` / `close_window` sobre `Attacker`). Si se pierden, el
enemigo deja de hacer daño y los tests de `Hitbox` aislada pasan igual — trampa nº2, literal.

Pero **fusionarlas en la biblioteca del rig no hace falta**, y conviene no hacerlo.
Comprobado sobre la escena: el `AnimationPlayer` del enemigo es hijo DIRECTO y se llama
exactamente así, y `ComponentLookup.find` prueba primero `get_node_or_null("AnimationPlayer")`
— sólo cae a "el primero de ese tipo a cualquier profundidad" si ese nombre falla. Un
`BodyAnimationPlayer` dentro del rig no se lo quita mientras el de combate conserve su
nombre y su sitio. Es la misma solución que ya lleva el jugador, y está escrita en un
comentario de `player.tscn`.

Lo que sí se rompe en silencio: `enemy_strike` anima **`Visuals/Body:scale`**, y
`Visuals/Body` es justamente el `Polygon2D` rectangular que el rig viene a sustituir. Esa
pista quedaría apuntando a un nodo inexistente —sin error, sin aviso— y el golpe perdería
su deformación. Reapuntarla a un hueso del rig, o retirarla. La otra pista,
`Visuals/Hitbox:position`, sobrevive: la hitbox no se toca.

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
