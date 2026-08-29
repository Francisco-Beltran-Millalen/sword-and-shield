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
│   ├── network/          # Sesión: el lobby que la abre y la cierra
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

## Decisiones tomadas

1. **Solo multijugador en red.** No hay cooperativo local en sofá. Cada cliente controla
   un personaje. Por eso el InputMap tiene **un solo juego de acciones**, sin prefijo por
   jugador.
2. **Cámara 2D por cliente**, colgada del personaje y encendida solo en el peer que lo
   controla (`PlayerCamera.set_local`). No hay pantalla compartida ni split-screen. Como
   cada cliente enmarca al suyo, los dos jugadores pueden estar en salas distintas — que
   es lo que hace viable la exploración divergente de un metroidvania cooperativo.
3. **Kits fijos por sesión.** Quien hospeda lleva espada; quien se une, escudo. El reparto
   es **determinista por `peer_id`** (`SessionState.kit_for`), así que cada cliente lo calcula
   solo: no se replica ni se acuerda por RPC, y un desajuste es imposible por
   construcción. `SessionState.assign()` queda para cuando el lobby permita elegir.

### Modelo de red: autoridad por jugador

Cada peer simula su propio personaje y replica el resultado por `MultiplayerSynchronizer`.
Un `Player` que no tiene la autoridad hace `return` al principio de `_physics_process` y
deja que el sincronizador escriba su posición.

Esto sustituye por completo al reenvío de intent por RPC del proyecto anterior, que metía
un viaje de ida y vuelta en cada pulsación. La contrapartida es que el cliente es
autoritativo sobre su propio personaje: aceptable en un cooperativo PvE, y a revisar si
alguna vez hay competitivo. Los enemigos, cuando lleguen, los simulará el host.

## Probar la red sin dos máquinas

```bash
# Terminal 1
godot -- --host

# Terminal 2
godot -- --join 127.0.0.1
```

Los argumentos van después de `--`, que es como Godot separa los suyos de los del juego.

## Decisiones aún abiertas

1. **Alcance de la sala.** Si las dos salas activas a la vez (una por jugador) se cargan
   simultáneamente o se descargan al alejarse. Lo decide el sistema de salas.
2. **Guardado.** Qué se persiste y cuándo (solo en puntos de guardado, o continuo).
