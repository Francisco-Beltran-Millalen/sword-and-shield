# Constitución de Arquitectura

> Sword & Shield — metroidvania de plataformas para 2 jugadores con kits asimétricos.
> Godot 4.7 · GDScript con tipado estático obligatorio.
>
> Sucesor del proyecto **Tension**. Este documento es su constitución portada, con dos
> enmiendas (§2 y §6) que salen de la auditoría de aquel proyecto y con una regla nueva
> (§13) que codifica la preferencia central del dueño del proyecto: **que el motor haga
> el trabajo**.

## Jerarquía del árbol de escenas

La arquitectura vive en el **árbol de escenas**, no en una pila de capas aparte. La
estructura padre-hijo del árbol impone la dirección de las dependencias por sí sola.

```
res:// (project.godot)
├── systems/world/world.tscn                  # Coordinador — ciclo de vida, cablea hijos
│   ├── level/zones/zone_*.tscn               # Zona activa: unidad de CARGA (contiene sus salas)
│   ├── characters/player/player.tscn         # Entidad (x2: espada y escudo)
│   │   ├── PlayerVisuals                     # Nodo hijo de presentación
│   │   ├── PlayerInputAdapter                # Nodo hijo adaptador de input
│   │   ├── Abilities/                        # §2: cada capacidad es un Nodo/escena
│   │   │   ├── SwordSwing                    #      con su Hitbox, AnimationPlayer, timers
│   │   │   └── ShieldGuard
│   │   └── Hurtbox (Area2D)                  # §13: capas separadas hitbox/hurtbox
│   ├── characters/enemy/enemy.tscn           # Entidad
│   │   ├── archetypes/                       # Composición de comportamiento
│   │   └── locomotion/                       # Motores de movimiento
│   ├── systems/camera/camera_rig.tscn        # Coordinación de cámara (2 jugadores)
│   ├── systems/network/                      # Replicación (MultiplayerSpawner/Synchronizer)
│   └── ui/hud/hud.tscn                       # Capa UI, solo lectura: el coordinador le EMPUJA (§5)
├── ui/debug/                                 # Overlays de depuración
└── autoloads/*.gd                            # Singletons (no están en el árbol de escena)
```

**Correspondencia con la estructura de carpetas (RULES.md §3):**

| Carpeta                    | Rol en el árbol de escenas                        |
| -------------------------- | ------------------------------------------------- |
| `systems/world/`           | Coordinador raíz — dueño del ciclo de vida        |
| `systems/camera/`          | Capa de coordinación — hijo bajo el coordinador   |
| `systems/network/`         | Capa de coordinación — replicación y sesión       |
| `characters/player/`       | Entidad — hijo bajo el mundo                      |
| `characters/enemy/`        | Entidad — hijo bajo el mundo                      |
| `components/`              | Nodos hijo reutilizables (§6)                     |
| `level/zones/`             | Contenido — zonas: la unidad de carga (ADR-001). Las salas viven dentro y NO se cargan |
| `level/building_kit/`      | Contenido compartido — tilesets y objetos         |
| `ui/`                      | Capa UI — hijo bajo el coordinador                |
| `autoloads/`               | Singleton transversal, fuera del árbol de escena  |

---

## Reglas

### §1 — Dirección del árbol: llamar hacia abajo, señalar hacia arriba

Un nodo **llama métodos** sobre sus hijos y descendientes. Un nodo se comunica **hacia
arriba** (padre o ancestro) únicamente emitiendo señales. Un nodo nunca guarda una
referencia a un padre o ancestro para llamarle métodos.

Las señales describen cosas que **ya ocurrieron**, no peticiones:

```
Good: landed, health_depleted, guard_broken, room_entered
Bad:  request_attack, do_apply_damage
```

_Este es el patrón natural de Godot — el árbol de escenas ya lo impone si uno lo respeta._

---

### §2 — Sin mutación lateral de estado

Un sistema nunca escribe estado que no le pertenece dentro de las variables de otro
sistema. Las fuerzas externas y las correcciones de posición viajan por la **API pública**
de la entidad destino, nunca por asignación directa de campos.

**Ejemplos de APIs legítimas:**

- `entity.take_damage(amount: int, source: Node)` — el sistema de daño llama a un método, no hace `health -= 10`
- `entity.apply_knockback(velocity: Vector2)` — el impacto aplica retroceso por método
- `entity.set_active(false)` — el coordinador desactiva una entidad por su setter público

**Antipatrón (mutación lateral):**

- `other_node.health = current_health - 10` — escritura directa en el estado de otro nodo
- `other_node.position.x += 50` — desplazar otro nodo en vez de llamar a un método

**Excepción — componentes de orquestación.** Un componente de orquestación compuesto
físicamente como Nodo hijo de su entidad anfitriona (p. ej. `PlayerBroker` bajo `Player`)
no es "otro sistema" para esta regla, siempre que:

1. El anfitrión invoque al orquestador (el padre llama hacia abajo, §1).
2. El orquestador no cachee ni retenga una referencia a su anfitrión — el anfitrión se
   pasa como parámetro explícito en cada invocación.
3. Las escrituras del orquestador sean las mismas que el anfitrión haría si el código
   estuviera en línea dentro de su propio trabajo por frame. La orquestación es una
   refactorización de código existente del anfitrión, no comportamiento nuevo entre
   componentes.

#### Enmienda 2026-08 — una capacidad es un Nodo, nunca un `RefCounted`

**Regla:** toda capacidad de un personaje (ataque, guardia, dash, parry, doble salto,
gancho) se implementa como **Nodo hijo o escena instanciada**, nunca como objeto
`RefCounted` ni como recurso con lógica.

**Por qué.** En Tension las capacidades ("transformaciones") eran `RefCounted`. Un
`RefCounted`:

- no puede tener nodos hijo (ni hitbox, ni `AnimationPlayer`, ni `Timer`),
- no recibe `_physics_process` ni `_ready`,
- no admite `@export` (nada configurable desde el editor),
- no puede escribir `velocity` ni tocar el `CharacterBody2D`.

Como no podía actuar, la capacidad tenía que **pedirle** al jugador que actuara. Eso
produjo una cola de mensajes hecha a mano —banderas `pending_dash`,
`pending_ground_pound`, `pending_anchor_stop`, `pending_double_jump` viviendo en un
componente compartido— y empujó el estado de cada capacidad al god-object `Player`, que
terminó en 1.000 líneas. La combinación de §2 ("no escribas estado ajeno") con un tipo
que *no puede* escribir el suyo propio no deja salida limpia: obliga a inventar un canal
de peticiones, que es exactamente lo que §1 prohíbe.

Con la capacidad como Nodo hijo, la excepción de "componente de orquestación" que esta
misma §2 ya contempla la cubre: es un hijo de su anfitrión, el anfitrión lo invoca hacia
abajo, y sus escrituras son las que el anfitrión haría en línea. Además la capacidad se
lleva consigo su hitbox `Area2D`, su `AnimationPlayer`, sus `Timer` y sus `@export`, y
puede desaparecer del árbol cuando el jugador no la tiene.

```
Good: characters/player/abilities/sword_swing.tscn  (Node2D)
        ├── Hitbox (Area2D)
        ├── AnimationPlayer
        └── CooldownTimer
      Player llama abilities.sword_swing.try_activate(self, delta)

Bad:  class SwordSwing extends RefCounted
      ... player.pending_attack = true   # cola de mensajes a mano
```

Corolario: si una capacidad necesita una bandera `pending_*` en otro nodo para funcionar,
está mal modelada. Conviértela en Nodo.

---

### §3 — Disciplina de acceso a NetworkManager _[específico del juego]_

Cualquier nodo puede **leer** `NetworkManager.is_active` y `NetworkManager.is_host_mode`.
Solo las escenas coordinadoras (`systems/network/lobby.gd`, `systems/world/`) pueden
**llamar** `NetworkManager.host()`, `.join()`, `.leave()` o `.reset()`.

Corolario: **el `NetworkManager` no conoce rutas de escena.** Avisa por señal
(`game_ready`, `session_ended`, `connection_error`) y quien escucha decide adónde ir. En
el proyecto anterior hacía `change_scene_to_file` en tres sitios y quedó atado al flujo
de aquel juego.

**Modelo de red: autoridad por jugador.** Cada peer simula su propio personaje y replica
el resultado; un nodo sin la autoridad no simula. Antes de preguntar por la autoridad hay
que comprobar `multiplayer.has_multiplayer_peer()`: tras una desconexión la escena vive
unos frames sin peer, y consultar ahí es un error de motor.

---

### §4 — Fuente única de verdad, incluidas las máquinas de estado

Cada hecho tiene exactamente un dueño. No hay copias locales de estado calculado por otro
sistema.

Estados mutuamente excluyentes = enum, nunca combinaciones de booleanos:

```
Good: enum State { IDLE, RUNNING, ATTACKING, GUARDING }
Bad:  var is_idle: bool; var is_attacking: bool
```

Cuando varios componentes internos de una entidad pueden escribir el mismo campo (varios
motores de física escribiendo `velocity`), exactamente uno es el **escritor activo** por
frame, elegido por una regla de despacho explícita. Ni listas de prioridad ni carreras de
"gana el último": se calcula el escritor activo una vez por frame y se despacha.

Cuando el estado del personaje se modela con un `AnimationTree` en modo StateMachine
(§13), **ese árbol es la fuente única**: no se duplica el estado en un enum paralelo del
script.

---

### §5 — El contexto de coordinación se empuja, no se consulta _[específico del juego]_

La capa de coordinación empuja un contexto por frame a cada entidad mediante un método
público dedicado. Las entidades **no** consultan al coordinador (sería una referencia
hacia arriba, prohibida por §1).

```
player.receive_coop_context(partner_position: Vector2, partner_guarding: bool)
```

El límite es la **propiedad del dato**, no el punto de llamada. Un servicio que lee
hechos de los nodos de su propia entidad (su `CharacterBody2D`, componentes hermanos,
hijos que la entidad posee) puede leerlos directamente — eso es autoconocimiento, no dato
entre sistemas. El dato entre sistemas (la vista del coordinador, el estado del otro
jugador) lo empuja la fuente o se accede por un accessor estrecho que la fuente provee.

---

### §6 — Responsabilidad única — límite duro de 400 líneas

Cada script tiene exactamente una responsabilidad. Los comportamientos se componen como
Nodos hijo en el árbol de escenas, no como métodos adicionales sobre una clase padre.

**Enmienda 2026-08 — el umbral es un límite duro, no una invitación a revisar.**

- **400 líneas es un tope duro para todo archivo nuevo.** Superarlo obliga a **dividir**,
  no a justificar. No hay revisión que "apruebe" un archivo de 450 líneas.
- **Única excepción admisible:** una entrada explícita en `ARCHITECTURE-MAP.md`, con
  **fecha** y **condición de salida** verificable, escrita como:
  `# excepción 2026-08-28 — player.gd 430 líneas — se divide cuando el kit de escudo
  salga de prototipo`. Sin fecha o sin la frase "se divide cuando X", la excepción no
  existe y el archivo se divide.
- Una excepción cuya condición de salida ya se cumplió es una violación, no una
  excepción. Revisarlas es parte de mantener el mapa (§ nota de mantenimiento del mapa).
- El tope se mide sobre el archivo completo, comentarios incluidos. Mover cien líneas a
  comentarios no cuenta como dividir.

**Por qué el diente.** En Tension la regla decía "300 líneas invita a revisar, no es
violación automática". El resultado medible: el mapa de arquitectura se llenó de párrafos
explicando por qué cada archivo grande podía seguir creciendo, y los tres archivos
vigilados llegaron a **1.000, 972 y 581 líneas** — mientras el propio mapa, ya
desactualizado, los registraba en 793 y 729. Una regla que solo pide justificación siempre
encuentra justificación: el coste de escribir un párrafo es menor que el de dividir un
archivo, así que el párrafo gana todas las veces. El límite tiene que ser una respuesta
binaria que no dependa del juicio del que está apurado.

---

### §7 — Composición sobre herencia — máximo 2 niveles

Profundidad de herencia ≤ 2 niveles (p. ej. `CharacterBody2D → Player`). Un tercer nivel
es violación. Los comportamientos que exigirían un tercer nivel se componen como Nodos
hijo.

En concreto: los arquetipos de enemigo (`characters/enemy/archetypes/`) y los modos de
locomoción (`characters/enemy/locomotion/`) son **composición**, no subclases de `Enemy`.
No existe `Enemy → FlyingEnemy → HomingFlyingEnemy`.

---

### §8 — `Input.*` está aislado en el adaptador de input

Las llamadas crudas a `Input.*` (`Input.is_action_pressed`, `Input.get_axis`,
`Input.is_action_just_pressed`) aparecen **solo** en la función designada de lectura de
input de una entidad o en su Nodo hijo adaptador de input. La simulación física, las
transiciones de estado y los sistemas de coordinación nunca llaman a `Input.*`.

Con dos jugadores locales, el sufijo de acción por jugador (`p1_attack` / `p2_attack`) o
el `device` del evento se resuelve **dentro** del adaptador; nada aguas abajo sabe qué
mando produjo el input.

---

### §9 — Los autoloads declaran el tiempo de vida de su estado

Cada variable de estado de un autoload lleva una de estas anotaciones:

- `# ephemeral: <razón>` — estado de sesión; se limpia entre partidas vía `reset()`
- `# persistent: <razón>` — dato de usuario que sobrevive cambios de escena y reinicios;
  nunca lo limpia `reset()`

---

### §10 — Las variables de intención son el límite de red _[específico del juego]_

El límite se sitúa en `PlayerIntent`: un objeto con lo que el jugador quiere hacer este
frame, sin decir de dónde viene. Lo produce una `IntentSource` — teclado
(`LocalIntentSource`), guion de test (`ScriptedIntentSource`) o, si algún día hace falta,
la red. Aguas abajo nada distingue el origen.

Con autoridad por jugador **el intent no viaja por la red**: cada peer lee su propio
teclado y replica el resultado ya simulado. La regla sigue viva porque es lo que permite
que los tests conduzcan a un jugador real sin tocar `Input`, y porque deja la puerta
abierta a una fuente de red si el modelo de autoridad cambia.

El proyecto anterior declaró esta clase y nunca la enhebró: su broker acabó con dos ramas
de ~40 líneas asignando los mismos campos, una para local y otra para red. Un solo camino
o la clase no sirve de nada.

---

### §11 — Testing nativo, basado en escenas

El testing automatizado usa frameworks nativos de Godot (GUT) corriendo dentro del
contexto del motor. Los tests corren sin ventana ni renderizado, pero pueden apoyarse en
el `SceneTree`. No se construyen abstracciones propias con el único fin de esquivar el
sistema de nodos de Godot para testear.

---

### §12 — Nombres semánticos antes que comentarios

El código prioriza nombres autoexplicativos sobre comentarios. Las abreviaturas estándar
(`dir`, `pos`, `vel`) son aceptables. Los comentarios en línea están **prohibidos** para
explicar _qué_ hace una lógica básica. Se reservan para explicar _por qué_ se tomó una
decisión, o _cómo_ funciona una matemática compleja (proyecciones vectoriales,
cuaterniones, etc.).

---

### §13 — El motor primero

Antes de escribir lógica a mano hay que verificar que Godot no la resuelva ya. Si existe
una feature nativa que cubre el caso, usarla no es opcional: escribir la versión propia
requiere justificar en el commit qué hace la nativa que no sirve.

La razón es de mantenimiento, no de elegancia. El código propio hay que depurarlo,
testearlo, documentarlo y portarlo entre versiones del motor; la feature nativa ya viene
con editor, serialización, herramientas de depuración y compatibilidad. Cada una de las
filas de abajo es un lugar donde Tension escribió código propio y pagó ese coste.

| Necesidad                          | Feature nativa                                                 | Qué se hizo mal en Tension                                                                          |
| ---------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Estados de personaje y frames de combate | `AnimationTree` en modo StateMachine + method/property tracks | Cinco contadores de frames a mano y cero `AnimationPlayer`                                            |
| Golpes y daño                      | `Area2D` con capas separadas hitbox / hurtbox                   | Daño resuelto por velocidad de choque leyendo `get_slide_collision()`                                 |
| Propiedades del terreno            | Custom data layers del `TileSet`                                | `atlas_coords == Vector2i(5, 0)` hardcodeado, `has_method()` y muestreo de 5 puntos (~40 líneas)      |
| Autotile / bordes de tiles         | Terrain sets del `TileSet`                                      | Colocación manual de tiles                                                                            |
| IA de navegación                   | `NavigationAgent2D` + `NavigationRegion2D`                      | Sondeo del entorno con raycasts a mano                                                                |
| Cámara                             | `position_smoothing_enabled`, `limit_*` de `Camera2D`           | `lerp` manual de la posición en `_process`                                                            |
| Datos del juego (stats, kits)      | `Resource` con `@export`                                        | Enum + diccionario de rutas a `.gd`                                                                   |
| Barrido de colisión / snap         | `move_and_collide(motion, true).get_travel()`                   | 8 iteraciones de `test_move` en búsqueda binaria                                                      |
| Validación de contenido            | `@tool` + `_get_configuration_warnings()` en el editor          | Avisos en runtime (`push_warning`) que solo se ven al jugar                                           |
| Aparición de entidades en red      | `MultiplayerSpawner` / `MultiplayerSynchronizer`                | Instanciación y sincronización por RPC a mano                                                         |

```
Good: var result := move_and_collide(motion, true)
      var safe_travel := result.get_travel() if result else motion

Bad:  # búsqueda binaria de 8 pasos con test_move()
      var lo := 0.0
      var hi := 1.0
      for i in 8:
          ...
```

Esta regla se aplica también hacia atrás: si aparece código propio que duplica una feature
nativa, sustituirlo es refactor prioritario, no deuda opcional.
