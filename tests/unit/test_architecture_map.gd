extends GutTest

## El mapa de arquitectura tiene que decir la verdad.
##
## `ARCHITECTURE-MAP.md` dedica su nota de mantenimiento a explicar que en el
## proyecto anterior registraba 793 y 729 líneas para archivos que ya iban por
## 1.000 y 972, y que "a partir de ahí nadie volvió a confiar en él". Cinco
## commits después de escribir esa nota, 15 de sus 27 filas volvían a tener el
## conteo mal.
##
## Una regla que depende de acordarse no se cumple. Esto la cuelga de la suite:
## el mapa deja de ser documentación de buena fe y pasa a ser algo que falla en
## rojo cuando miente.

const MAPA := "res://docs/adr/ARCHITECTURE-MAP.md"
## §6 de la constitución: tope duro, no una invitación a justificarse.
const TOPE_DE_LINEAS := 400
## Dónde vive el código de producción. `tests/` y `addons/` quedan fuera.
const RAICES: Array[String] = [
	"res://autoloads", "res://characters", "res://components",
	"res://level", "res://systems", "res://ui",
]

var _filas: Dictionary = {}


func before_all() -> void:
	_filas = _leer_filas()


func test_el_mapa_se_puede_leer() -> void:
	assert_gt(_filas.size(), 0,
			"sin filas no hay nada que verificar: ¿cambió el formato de la tabla?")


func test_cada_fila_apunta_a_un_archivo_que_existe() -> void:
	for ruta: String in _filas:
		assert_true(FileAccess.file_exists("res://" + ruta),
				"el mapa registra '%s' y ese archivo no existe" % ruta)


func test_el_conteo_de_lineas_coincide_con_el_archivo() -> void:
	for ruta: String in _filas:
		var declaradas: int = _filas[ruta]
		var reales := _lineas_de("res://" + ruta)
		assert_eq(reales, declaradas,
				"'%s': el mapa dice %d líneas y tiene %d. Se actualiza en el MISMO commit que el código."
				% [ruta, declaradas, reales])


func test_ningun_archivo_pasa_del_tope_de_lineas() -> void:
	for ruta: String in _filas:
		assert_lte(_lineas_de("res://" + ruta), TOPE_DE_LINEAS,
				"'%s' pasa de %d líneas (§6). El tope es duro: se divide, no se justifica."
				% [ruta, TOPE_DE_LINEAS])


func test_ninguna_clase_de_produccion_queda_sin_registrar() -> void:
	for ruta in _scripts_de_produccion():
		assert_true(_filas.has(ruta),
				"'%s' no está en el mapa. Una clase nueva se registra al construirla." % ruta)


## --- Utilidades ---

## Se cuentan saltos de línea, que es lo que cuenta `wc -l`: si el test midiera
## de otra forma, las 27 filas fallarían por un off-by-one.
func _lineas_de(ruta: String) -> int:
	return FileAccess.get_file_as_string(ruta).count("\n")


## Filas de la tabla `## Built`, como `ruta -> líneas declaradas`. Las tablas de
## excepciones, aplazados y retirados tienen otra forma y no se miran.
func _leer_filas() -> Dictionary:
	var encontradas: Dictionary = {}
	var expresion := RegEx.new()
	expresion.compile("^\\| *`[^`]+` *\\| *`([^`]+)` *\\((\\d+)\\)")

	var en_built := false
	for linea in FileAccess.get_file_as_string(MAPA).split("\n"):
		if linea.begins_with("## Built"):
			en_built = true
			continue
		if en_built and (linea.begins_with("### ") or linea.begins_with("## ")):
			break
		if not en_built:
			continue
		var encaje := expresion.search(linea)
		if encaje != null:
			encontradas[encaje.get_string(1)] = int(encaje.get_string(2))
	return encontradas


func _scripts_de_produccion() -> Array[String]:
	var encontrados: Array[String] = []
	for raiz in RAICES:
		_recorrer(raiz, encontrados)
	encontrados.sort()
	return encontrados


func _recorrer(carpeta: String, acumulador: Array[String]) -> void:
	var dir := DirAccess.open(carpeta)
	if dir == null:
		return
	for archivo in dir.get_files():
		if archivo.ends_with(".gd"):
			acumulador.append((carpeta + "/" + archivo).trim_prefix("res://"))
	for subcarpeta in dir.get_directories():
		_recorrer(carpeta + "/" + subcarpeta, acumulador)
