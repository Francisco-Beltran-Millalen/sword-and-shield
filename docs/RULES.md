# REGLAS DEL PROYECTO

> Archivo único de convenciones. Léelo completo antes de escribir código.
> Las reglas de arquitectura (qué llama a qué, dónde vive el estado) están en
> `docs/adr/CONSTITUTION.md`. Este documento cubre el **cómo se escribe**.

Godot **4.7** · GDScript · **tipado estático obligatorio** en variables, parámetros y
tipos de retorno.

---

## 1. Nomenclatura

### 1.1 Tabla de estilos

| Elemento                       | Estilo                                  | Ejemplo                          |
| ------------------------------ | --------------------------------------- | -------------------------------- |
| Variable local / miembro       | `snake_case`                            | `player_speed`                   |
| Variable privada               | `_snake_case`                           | `_cooldown_left`                 |
| Constante                      | `SCREAMING_SNAKE_CASE`                  | `MAX_SPEED`                      |
| Enum (nombre)                  | `PascalCase`                            | `GameState`                      |
| Enum (valor)                   | `SCREAMING_SNAKE_CASE`                  | `GameState.PAUSED`               |
| Clase (`class_name`)           | `PascalCase`                            | `PlayerController`               |
| Nodo en escena                 | `PascalCase`                            | `PlayerSprite`, `HitboxArea`     |
| Función / método               | `snake_case`                            | `take_damage()`                  |
| Función privada                | `_snake_case`                           | `_initialize()`                  |
| Señal                          | `snake_case` (evento pasado)            | `health_changed`                 |
| Callback de señal              | `_on_nodo_senal()`                      | `_on_hitbox_body_entered()`      |
| Archivo `.gd`                  | `snake_case` (coincide con `class_name`)| `player_controller.gd`           |
| Archivo `.tscn`                | `snake_case`                            | `main_menu.tscn`                 |
| Archivo `.tres`                | `snake_case`                            | `sword_kit.tres`                 |
| Imagen / sprite                | `snake_case`                            | `player_idle.png`                |
| Audio                          | `sfx_` / `bgm_` + `snake_case`          | `sfx_parry.wav`, `bgm_caves.ogg` |
| Fuente                         | `snake_case`                            | `pixel_font.ttf`                 |
| Shader                         | `snake_case`                            | `water_ripple.gdshader`          |
| Animación (AnimationPlayer)    | `snake_case`                            | `idle`, `run`, `attack_windup`   |
| Archivo de test                | `test_` + `snake_case`                  | `test_player_controller.gd`      |

### 1.2 Reglas rápidas (correcto vs incorrecto)

| Concepto              | ✅ Correcto                          | ❌ Incorrecto                                |
| --------------------- | ------------------------------------ | -------------------------------------------- |
| Variable local        | `var player_speed: float`            | `var PlayerSpeed`                            |
| Constante             | `const MAX_HEALTH: int = 100`        | `const maxHealth = 100`                      |
| Clase                 | `class_name PlayerController`        | `class_name player_controller`               |
| Estado con enum       | `enum State { IDLE, ATTACKING }`     | `var is_idle: bool; var is_attacking: bool`  |
| Señal                 | `signal health_changed(value: int)`  | `signal OnHealthChanged(v)`                  |
| Privado               | `func _calculate() -> void:`         | `func calculateInterno():`                   |
| Función tipada        | `func heal(amount: int) -> void:`    | `func heal(amount):`                         |
| Inferencia (visible)  | `var dir := Vector2.ZERO`            | `var dir = Vector2.ZERO` (sin tipo)          |

---

## 2. Tipado

```gdscript
var speed: float = 200.0          # siempre tipado
var dir := Vector2.ZERO           # inferencia := solo si el tipo es obvio en la línea
func heal(n: int) -> void:        # parámetros y retorno siempre tipados
@onready var _spr: Sprite2D = $Sprite2D
```

- `:=` se usa cuando el tipo se lee en la misma línea; si no, tipo explícito.
- Los arrays y diccionarios se tipan cuando es posible: `var enemies: Array[Enemy] = []`.
- Nunca `var x` sin tipo ni valor.

---

## 3. Estructura del proyecto

Se sigue la recomendación oficial de Godot: **agrupar por dominio/contexto, no por tipo de
archivo**.
Ver: https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html

Cada elemento del juego (personaje, sistema, pantalla) es una carpeta autocontenida con su
escena, script y subrecursos juntos. Los assets compartidos viven en su propio nivel
superior. La carpeta `docs/` se excluye de la importación con `.gdignore`.

```
res://
├── autoloads/                       # §9: singletons con anotación de tiempo de vida
├── characters/
│   ├── player/                      # Jugador (kits espada / escudo)
│   │   ├── player.tscn / player.gd
│   │   ├── player_input_adapter.gd
│   │   └── player_visuals.gd        # §2: cada capacidad es un Nodo/escena aquí
│   └── enemy/
│       ├── enemy.tscn / enemy.gd
│       ├── archetypes/              # Composición de comportamiento (no subclases)
│       └── locomotion/              # Motores de movimiento
├── components/                      # §6: Nodos hijo reutilizables
├── systems/
│   ├── world/                       # Coordinador raíz — ciclo de vida y cableado
│   ├── network/                     # Sesión: el lobby que la abre y la cierra
│   └── camera/                      # Plataforma de cámara para 2 jugadores
├── level/
│   ├── rooms/                       # Salas del metroidvania (.tscn)
│   └── building_kit/                # Contenido compartido de construcción
│       ├── objects/                 # Props, plataformas, puertas
│       └── tilesets/                # TileSets con terrain sets y custom data layers
├── ui/
│   ├── hud/
│   └── debug/                       # Overlays de depuración
├── tests/                           # §11: suite GUT
│   ├── unit/
│   └── integration/
├── addons/                          # Recursos de terceros (GUT, etc.)
├── docs/                            # Documentación (excluida vía .gdignore)
│   ├── .gdignore
│   ├── RULES.md
│   └── adr/
│       ├── CONSTITUTION.md
│       └── ARCHITECTURE-MAP.md
└── project.godot
```

- Cada carpeta de dominio es dueña de sus `.tscn`, `.gd` y subrecursos juntos.
- Los autoloads van estrictamente en `autoloads/`.
- Los recursos de terceros van en `addons/`.
- Los tests en `tests/`, espejando la estructura de dominios.
- `level/building_kit/` contiene lo reutilizable entre salas; `level/rooms/` contiene las
  salas concretas y no define contenido propio nuevo.

---

## 4. Scripts — orden interno (obligatorio)

Basado en la [guía de estilo oficial de Godot 4](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html#code-order).

```
01. @tool, @icon, @static_unload
02. class_name
03. extends
04. ## doc comment

05. signals
06. enums
07. constants
08. static variables
09. @export variables
10. resto de variables regulares
11. @onready variables

12. _static_init()
13. resto de métodos estáticos
14. virtuales built-in sobreescritos:
     1. _init()
     2. _enter_tree()
     3. _ready()
     4. _process()
     5. _physics_process()
     6. resto de virtuales
15. métodos custom sobreescritos
16. resto de métodos: públicos → privados (_) → callbacks de señales (_on_)
17. inner classes
```

**Claves:** `@onready` va después de TODAS las variables regulares. Las inner classes
siempre al final del archivo. Este orden es obligatorio.

---

## 5. Reglas clave de Godot

- Señales por encima de llamadas directas entre nodos no emparentados (§1).
- `@export` para todo valor configurable desde el editor; nada de constantes de tuneo
  enterradas en el script.
- `@onready` para referencias a hijos; nunca rutas largas dentro de `_process()`.
- No `get_node("/root/...")` — referencias relativas o autoloads.
- Autoloads solo para sistemas globales reales (`GameManager`, `AudioManager`,
  `SaveSystem`), con la anotación de tiempo de vida de §9.
- Doc comments con `##`, comentarios internos con `#` (y solo para el *por qué*, §12).
- Enums multilínea con trailing comma.
- Antes de escribir lógica a mano, revisar §13 de la constitución: casi siempre el motor
  ya lo resuelve (`AnimationTree`, `Area2D`, custom data layers, `NavigationAgent2D`,
  `Resource`, `MultiplayerSpawner`…).
- Ningún archivo nuevo supera **400 líneas** (§6, límite duro).

---

## 6. Git

Formato de commit: `type: descripción breve en inglés`

- `feat:` — funcionalidad nueva
- `fix:` — corrección de bug
- `refactor:` — reestructuración sin cambio funcional
- `test:` — tests
- `docs:` — documentación
- `assets:` — assets (sprites, audio, etc.)
