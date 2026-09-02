# Sword and Shield — contexto del proyecto

Plataformero **metroidvania de 2 jugadores en red**, con kits asimétricos: un jugador
lleva espada, el otro escudo. Godot 4.7, GDScript con tipado estático obligatorio.

Sucede al proyecto `../geometry-tension` ("Tension"), que quedó **pausado** el 28 de
agosto de 2026. De allí se portó la infraestructura genérica; el juego en sí se descartó.

---

## Comandos

```bash
# Tests (no hay escena runner: se invoca GUT por línea de comandos)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Un solo archivo de test
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_combat.gd -gexit

# Probar la red sin dos máquinas (los `--` separan los argumentos del juego)
godot -- --host          # terminal 1
godot -- --join 127.0.0.1   # terminal 2

# VER el juego: Movie Maker nativo escribe una secuencia de PNG del viewport
# (extensión .png = fotogramas sueltos; .avi = MJPEG, y cuesta 2 s y 5 MB por
# fotograma). Siempre 1920x1080: ignora --resolution. Se graban N fotogramas y se
# elige uno; esperar "los segundos que hagan falta" y disparar es una apuesta.
godot --path . --scene res://systems/world/world.tscn \
      --write-movie /tmp/mov/shot.png --fixed-fps 60 --quit-after 120

# Y una partida REAL de dos, que es el único caso que representa al juego:
godot --path . --write-movie /tmp/h/f.png --fixed-fps 30 --quit-after 300 -- --host &
sleep 3
godot --path . --write-movie /tmp/c/f.png --fixed-fps 30 --quit-after 300 -- --join 127.0.0.1 &

# Ver las formas de colisión mientras corre: lo da el motor, no hace falta código
godot --path . --debug-collisions --scene res://systems/world/world.tscn
```

**F3 abre el panel de depuración** (zona, sala, peer, golpes). En una GRABACIÓN no
sirve —`--write-movie` no tiene teclado—: hay que poner `visible_al_arrancar` a
`true` en el `DebugOverlay` de `world.tscn` antes de grabar.

**Para capturar hace falta ventana.** En `--headless` la captura del viewport da
`Parameter "t" is null` y `--write-movie` casca con SIGSEGV. Es lo primero que se
prueba y no funciona.

**El conteo de archivos es la señal, no el mensaje.** Movie Maker imprime "1 frames"
tras escribir 120: `ls | wc -l`, igual que con los Scripts de GUT.

`--write-movie` no depende del foco, del compositor ni de que la pantalla esté
desbloqueada. `spectacle -b -n -a` (KDE) sirve para una captura suelta **con alguien
delante**: toma la ventana ACTIVA, así que con la pantalla bloqueada devuelve la
pantalla de bloqueo con exit 0 y sin un aviso — el fallo es indistinguible del acierto.

Lo que ninguna de las dos hace es **pilotar**: para conducir a alguien por la sala se
sustituye su `IntentSource` por uno guionizado, que es lo que ya hacen los tests.

---

## Cómo trabajar aquí

**Preferencia explícita del dueño: que el motor haga el trabajo, no el código propio.**
Antes de escribir lógica a mano, busca la feature nativa de Godot. El proyecto anterior
acumuló deuda justo por lo contrario. Está formalizado como **§13 — El motor primero** en
`docs/adr/CONSTITUTION.md`, con una tabla de casos concretos.

**El objetivo actual es la estructura del proyecto, no el contenido del juego.** Se busca
código reutilizable y desacoplado: componentes que sirvan igual a un jugador, un enemigo o
una trampa. Un componente que castee a `Player` o asuma quién es su padre está mal.

Lee `docs/adr/CONSTITUTION.md` antes de cambios de arquitectura. Sus dos enmiendas
importantes, ambas nacidas de deuda real del proyecto anterior:

- **§2 — una capacidad es un Nodo, nunca un `RefCounted`.** Sin esto no puede tener
  hijos (hitbox, `AnimationPlayer`, timers), y su estado acaba en el anfitrión.
- **§6 — 400 líneas es tope duro,** no una invitación a justificarse. En el proyecto
  anterior el umbral "blando" dejó archivos de 1.000 líneas con párrafos explicando por
  qué podían crecer más.

`docs/adr/ARCHITECTURE-MAP.md` se actualiza **en el mismo commit** que el código. Ya no
depende de acordarse: `tests/unit/test_architecture_map.gd` compara cada fila con el
archivo real y falla en rojo si el mapa miente, si una clase de producción no está
registrada o si alguien pasa de 400 líneas (§6).

---

## Trampa recurrente: verde no significa funcionando

Ha pasado **nueve veces** en este proyecto. Los tests pasaban y la funcionalidad no existía:

1. `room_scaffold.gd` no compilaba. Un error de parseo deja al nodo **sin script** sin
   romper la instanciación de la escena: las salas quedaban sin suelo y la suite seguía
   en verde.
2. Los `AnimationPlayer` estaban vacíos, así que nadie llamaba a `Hitbox.enable()` y la
   espada no hacía daño. Los tests de `Hitbox` aislada pasaban igual.
3. Faltaba que la `Hitbox` llamara a `Hurtbox.receive()`. La cadena quedaba abierta: la
   ventana se abría y el daño no llegaba a aplicarse nunca.
4. `RoomScaffold` dibujaba el hueco de paso a 514 px del suelo y las plataformas a 401,
   contra un salto de 101. Las dos zonas eran intransitables: el jugador caía en la
   primera sala y no podía salir. El juego arrancaba sin un solo error y la suite daba
   119/119, porque **ningún test conducía a un jugador por la geometría**.

5. `arrival_point()` de una puerta es su **centro**, y `World._place_players` dejaba a
   los jugadores ahí: al cruzar aparecían DENTRO del área de la puerta de destino, que
   volvía a cumplir sus condiciones y pedía volver por donde se vino. Medido: veinte
   cargas de zona en cuatro segundos, en bucle. La suite daba 151/151 porque **ningún
   test cruzaba una puerta** — solo se podía descubrir cuando la geometría del punto 4
   dejó de ser intransitable.

6. El empuje del golpe que te mata se guardaba en `_pending_impulse` y no se gastaba
   nunca: la rama `DOWNED` de `Player._physics_process` retornaba antes del único sitio
   que lo consumía. Y el golpe letal llega SIEMPRE con el jugador ya caído, porque
   `HealthComponent.take_damage` emite `depleted` dentro de la llamada y `DamageReceiver`
   pide el empuje once líneas después. Segundo y medio más tarde, al revivir, la cola
   salía entera: medido, (363, -200) y 42 px de deriva. La suite daba 176/176 porque
   **ningún test mataba a un jugador con empuje y lo revivía**.
7. Las formas de colisión de `enemy.tscn` eran sub-recursos **compartidos entre
   instancias**, y `_apply_body_size` las escribe desde el arquetipo: el último enemigo
   en entrar al árbol le imponía su cuerpo, su hurtbox y su radio de visión a todos los
   demás — y el `Polygon2D`, que no es recurso compartido, se quedaba con el suyo, así
   que el bicho acababa con un cuerpo de 120 y un dibujo de 44. La promesa "un enemigo
   nuevo es un `.tres`" no se sostenía, y **no se veía porque solo había un arquetipo**.
   Se arregla con `resource_local_to_scene`, no con código. Va en las **cuatro** formas,
   incluida la de la garra, que hoy nadie escribe desde el arquetipo: el día que el
   alcance del golpe salga del dato —`attacks` ya está ahí— el fallo vuelve idéntico, y
   con la documentación diciendo que estaba resuelto.
8. `Camera2D.offset` **se salta los `limit_*`**. `player_camera.gd` metía ahí su
   `look_ahead_y` de -48 px, así que con la cámara topada contra el suelo de la sala la
   vista se iba 48 px por debajo del límite: quien estaba de pie en el suelo lo veía
   FUERA DE CUADRO, y él mismo asomaba por el borde inferior. Estaba anotado como "el
   host encuadra peor que el cliente" y parecía cosa de la red; no lo era — la asimetría
   venía de que los dos jugadores aparecían a alturas distintas. El arreglo es mover el
   desplazamiento a `position`, que sí cuelga del personaje y sí respeta los límites.
   La suite daba 187/187 porque **ningún test mira lo que se ve**: sólo la colisión.
   Y el `-40` en Y de `World._place_players` era el parche de cuando el punto de llegada
   era el centro de la sala; al pasar a devolver el suelo, ese parche dejó a los dos
   jugadores flotando. Un margen mágico sobrevive al motivo que lo puso.

9. El propio panel de depuración recién escrito **no compilaba**:
   `NOTIFICATION_VISIBILITY_CHANGED` es de `CanvasItem`, y un `CanvasLayer` no lo es.
   El nodo se quedó sin script, la escena se instanció igual y los 209 tests seguían
   verdes — sólo salió al lanzar host y cliente de verdad. Novena vez, y la primera
   con un test que la caza: `test_zone_depth.gd` instancia `world.tscn` y exige que
   cada nodo CONSERVE su script, que es la comprobación que faltaba desde el punto 1.

**Consecuencias prácticas:**

- **GUT omite en silencio los scripts que no compilan** y aun así imprime *"All tests
  passed"*. La señal fiable es el conteo de **Scripts**, no el mensaje final.
- Prueba recorridos completos, no piezas sueltas. `tests/integration/test_damage_chain.gd`
  es el modelo: va de la intención al descuento de salud, y
  `tests/integration/test_room_traversal.gd` conduce a un jugador real por la sala.
- **Mide, no deduzcas.** El alcance del jugador se mide conduciéndolo, y la geometría se
  compara contra esa medida. Tres diseños de escalera pasaron la aritmética y se atascaron
  al pilotarlos: el desplazamiento lateral que cabe en un salto no es el que parece.
- **Quien se suscribe tarde no ve el primer valor.** El `_ready` de un hijo corre antes
  que el del padre, así que la emisión inicial de un componente ya ha pasado cuando el
  padre se conecta a él: `HealthComponent` emite su `health_changed` en el `_ready`
  (`health_component.gd`) y `Player` se suscribe en el suyo, o sea después. Por eso el
  `World` engancha el HUD al **componente** y **antes** de meter al jugador en el árbol.
  Enganchado al `Player`, la barra se queda a cero hasta el primer golpe — y un test que
  solo compruebe "recibe daño y baja" pasa igual. `test_hud.gd` afirma el valor inicial
  justamente por eso.
- **Un comentario también miente, y nadie lo compila.** `rpc_change_zone` decía esperar
  un frame "de cortesía para que el cliente vaya por delante". Lo que de verdad hacía ese
  `await` era sacar la carga de zona del callback de física — la pide el `body_entered` de
  una puerta, y quitar un `CollisionObject2D` ahí está prohibido. Creerle al comentario y
  condicionar la espera a que hubiera red tumbaba los cinco tests de cruce y llenaba la
  consola de ~1.800 errores. Ahora la carga va diferida siempre y por su razón real.
- **Un fallo que solo aparece con dos, no aparece con uno.** Los sub-recursos compartidos
  y el reparto de reaparición son la misma figura: con una sola instancia el código está
  bien. Cuando algo se configura por datos, el test que sirve monta **dos** con datos
  distintos.
- **Ejecuta el juego de verdad** antes de dar algo por terminado. Los tres primeros
  fallos aparecieron al lanzar host y cliente, no en la suite. El cuarto ni siquiera:
  arrancaba limpio en ambos extremos y solo salió al medir la geometría contra el
  alcance del jugador.

---

## Decisiones tomadas

| Decisión | Por qué |
| --- | --- |
| **Solo multijugador en red.** No hay cooperativo local en sofá | Cada cliente controla un personaje; por eso el InputMap tiene un solo juego de acciones, sin prefijo `p1_`/`p2_` |
| **Cámara por cliente**, colgada del personaje y encendida solo en su peer | Permite que los dos jugadores estén en sitios distintos, que es lo que hace viable la exploración divergente |
| **Autoridad por jugador**: cada peer simula el suyo y replica | Elimina el reenvío de intent por RPC del proyecto anterior, que metía ida y vuelta en cada pulsación. Un `Player` sin autoridad hace `return` en `_physics_process` |
| **La zona es la unidad de carga; la sala solo encuadra** | Ver `docs/adr/rationale/adr-001-zonas-y-salas.md`. Cargar por sala con dos jugadores independientes es una fuente permanente de desincronización |
| **Kits fijos, repartidos por `peer_id`** (host = espada) | Determinista: cada cliente lo calcula solo, no se replica. Un desajuste es imposible por construcción |

**Dos preguntas distintas, dos formas distintas.** "¿Simulo yo esta entidad?" es
`is_multiplayer_authority()`; "¿hay sesión de red?" es `NetworkManager.is_active`.
`has_multiplayer_peer()` no responde a ninguna de las dos y ya no se usa en producción:
medido, devuelve `true` sin sesión, porque Godot instala un `OfflineMultiplayerPeer` con
`get_unique_id() == 1`.

Se apoya en una invariante: **siempre hay un peer asignado**, porque `reset()` restaura el
peer offline en vez de dejar `null`. Sin ella queda una ventana —solo la abría `reset()`—
en la que preguntar por la autoridad es un error de motor, y de la que había que
defenderse en doce sitios. Dos casos que la invariante no cubre y siguen vigilados:
`is_multiplayer_authority()` sobre un nodo **fuera del árbol** también revienta, y un
`rpc_id` a un peer que ya se fue igual. `test_network_authority.gd` fija los tres.

Ojo con una consecuencia: un nodo con autoridad de otro peer se comporta como remoto
aunque se juegue en un solo proceso — por eso un segundo jugador montado a mano en un test
no lo coloca `_place_players`.

---

## Mapa rápido

```
components/          Reutilizables, sin conocer a su dueño
  combat/            AttackData (Resource) · Attacker · DamageReceiver
  hitbox · hurtbox · guard_box · health_component · stats_component · state_machine
  component_lookup   Cómo una entidad encuentra sus piezas (sin `class_name`)
characters/player/   Player (orquestador delgado) · Locomotion · IntentSource
  kits/              PlayerKit (Nodo) → SwordKit · ShieldKit
    attacks/         Un .tres (AttackData) por golpe
characters/enemy/    Enemy · EnemyArchetype (Resource) · AIIntentSource · Perception
  archetypes/        Un .tres por tipo de enemigo
  attacks/           Sus AttackData, junto a los del jugador en forma
level/systems/       Zone · RoomBounds · ZoneDoor · RoomScaffold (todos @tool)
level/zones/         zone_verdant · zone_cinder (5 salas cuadradas cada una)
systems/             world/ · network/ (lobby) · camera/
ui/hud/              Hud — capa de solo lectura; el World le empuja, no pregunta
autoloads/           NetworkManager · GameEvents · SessionState (los tres, sin `class_name`)
```

**Patrones a imitar** (los mejores del repo): `stats_component.gd` descubre sus
modificadores solo con `child_entered_tree` — desbloquear una habilidad es colgar un nodo.
`zone.gd` busca por **tipo** (`find_children("*", "RoomBounds")`), no por nombre.
`IntentSource` se sustituye por nodo, así que los tests conducen a un jugador real sin
tocar `Input`.

**El enemigo no estrena ningún sistema.** Usa `Locomotion`, `Attacker`, `Hitbox`,
`Hurtbox`, `DamageReceiver`, stats y salud del jugador sin una línea añadida para él; lo
único propio es `AIIntentSource`, que rellena el mismo `PlayerIntent` que el teclado. Si
para meter una entidad nueva hiciera falta escribir movimiento o combate propios, el
problema no es la entidad: son los sistemas, que estaban acoplados al jugador.

**Un `class_name` nuevo no existe hasta que Godot reimporta.** Crear el archivo desde
fuera del editor no lo registra en el caché de clases globales: los scripts que lo usan no
compilan, el nodo se queda **sin script** y la escena se instancia igual. Tras añadir una
clase, `godot --headless --import --path .`. Y para lanzar un script suelto hace falta
`--path .`, o no se ve el proyecto y pasa lo mismo.

**Con `-s`, en `_init()` todavía no hay autoloads.** El script pasado a `-s` ES el
MainLoop, así que su `_init()` corre ANTES de que la SceneTree los instale: un frame
después los tres están y se resuelven como identificadores globales sin más. Medido —
la causa es el momento, no el registro, y `--path .` no cambia nada. Consecuencia
concreta: un script `-s` que nombre un autoload en su propio texto no compila, y si de
paso carga `world.gd` o `attacker.gd` se los lleva por delante en cascada
(`Identifier not found: NetworkManager`), dejando los nodos SIN script. Por eso GUT
funciona: `addons/gut/gut_cmdln.gd:25-28` espera a que haya main loop antes de cargar
nada.

**`GameEvents` no es un atajo.** Un evento entra ahí solo si emisor y receptor no pueden
conocerse por el árbol. Si se conocen, va una señal local con `bind` — las condiciones
están escritas en el propio archivo.

---

## Qué falta

Por orden de lo que más desbloquea:

1. **HUD — esqueleto puesto, contenido no.** `Hud` ya muestra la salud de los dos
   jugadores y por qué una puerta no se abre. Faltan el estado del kit (guardia, combo),
   las habilidades desbloqueadas, la pantalla de derrota y cualquier arte: todo son
   `ProgressBar` y `Label` desnudos.
2. **Progresión.** El mecanismo existe (`StatModifierNode`); faltan las habilidades y las
   puertas que las exijan.
3. **Guardado.** No hay nada: ni `ResourceSaver`, ni `user://`. Es el corazón del género.
   Decidida ya la **forma**, no la fecha: guarda el host, un archivo, estado del mundo — el detalle
   y el porqué, en `ARCHITECTURE-MAP.md` → *Deferred*. Va **después** de la progresión: sin
   habilidades no hay esquema que inventar.
4. **Mapa.**
5. **Tileset y arte.** Todo son `Polygon2D`. `RoomScaffold` es geometría provisional y
   está marcado para retirarse cuando haya `TileMapLayer` con terrain sets. La
   **legibilidad ya no espera a eso**: el graybox tiene `default_clear_color` propio,
   cuatro colores por rol en el andamio —la losa de un solo sentido se distingue del
   suelo macizo—, dos capas de fondo y una de primer plano con `Parallax2D`, el
   `room_id` escrito en las cuatro esquinas de cada sala y las dos zonas separadas por
   temperatura. Lo que falta es arte de verdad, no que se entienda el nivel.
6. **Audio.** Nada.

También pendientes, anotados con su disparador en `ARCHITECTURE-MAP.md` → *Deferred*:
`tether_pressed` e `interact_pressed` viajan en el intent pero **nadie los consume** (el
salto largo y la interacción); `DAMAGE_POWER` y `KNOCKBACK_DEALT` están declarados en los
stats y nadie los lee — cuando se implementen van en el `Attacker`, no en la entidad; y un
mecanismo de reagrupamiento por si la dispersión dentro de una zona molesta en pruebas.
