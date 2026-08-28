# Sword & Shield

Metroidvania de plataformas en 2D para **dos jugadores con kits asimétricos**: un jugador
lleva espada, el otro escudo. El progreso depende de que ambos kits se combinen — ninguno
de los dos resuelve una sala solo.

Sucede al proyecto **Tension** (juego de física con una cuerda elástica entre dos
jugadores), que se abandona. Se conservan sus documentos de arquitectura, con enmiendas
que salen de la auditoría de aquel código.

Estado: **arranque**. No hay jugabilidad todavía.

## Stack

| Aspecto       | Elección                                      |
| ------------- | --------------------------------------------- |
| Motor         | Godot 4.7                                     |
| Lenguaje      | GDScript, tipado estático obligatorio         |
| Tests         | GUT (addon en `addons/`)                      |
| Principio guía| El motor primero (CONSTITUTION §13)           |

## Estructura

```
res://
├── autoloads/            # Singletons (con anotación de tiempo de vida)
├── characters/
│   ├── player/           # Jugador y sus capacidades (Nodos, no RefCounted)
│   └── enemy/
│       ├── archetypes/   # Comportamiento por composición
│       └── locomotion/   # Motores de movimiento
├── components/           # Nodos hijo reutilizables
├── systems/
│   ├── world/            # Coordinador raíz
│   ├── network/          # Sesión y replicación
│   └── camera/           # Cámara de 2 jugadores
├── level/
│   ├── rooms/            # Salas
│   └── building_kit/     # objects/ y tilesets/ compartidos
├── ui/
│   ├── hud/
│   └── debug/
├── tests/                # unit/ e integration/
├── addons/               # Terceros (GUT)
└── docs/
    ├── RULES.md          # Convenciones de código
    └── adr/
        ├── CONSTITUTION.md    # Reglas de arquitectura §1–§13
        └── ARCHITECTURE-MAP.md
```

## Tests

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Los tests corren sin ventana pero dentro del motor, sobre el `SceneTree` real
(CONSTITUTION §11). No hay escena de runner: el comando de arriba es la única forma
soportada de lanzarlos.

## Documentación

- `docs/adr/CONSTITUTION.md` — reglas de arquitectura. Lo primero que hay que leer.
- `docs/RULES.md` — nomenclatura, tipado, orden dentro de un script, estructura.
- `docs/adr/ARCHITECTURE-MAP.md` — registro de lo construido. Se actualiza en el mismo
  commit que el código.

## Decisiones pendientes

Ninguna de estas está tomada. Afectan al diseño, así que se resuelven antes de construir
contenido que dependa de ellas.

1. **Modelo de cámara para 2 jugadores.** Opciones: cámara compartida con tope de
   separación / split-screen dinámico / salas independientes por jugador. Condiciona el
   diseño de **todas** las salas (tamaño, si los jugadores pueden separarse, si una sala
   puede tener dos focos de acción). Es la decisión más bloqueante de las tres.
2. **Alcance del cooperativo.** Local en sofá, en red, o ambos. Determina si las reglas
   §3 y §10 de la constitución (NetworkManager y variables de intención como límite de
   red) siguen vigentes o se retiran.
3. **Asignación de kits.** Espada y escudo fijos por jugador durante toda la partida, o
   intercambiables en mitad de la partida. Afecta al diseño de puzles y a si las
   capacidades tienen que poder entrar y salir del árbol de escena en caliente.
