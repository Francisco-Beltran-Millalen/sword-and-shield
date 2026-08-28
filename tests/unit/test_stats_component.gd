extends GutTest

## Stats base + modificadores apilables, con descubrimiento automático de hijos.

const StatsScript := preload("res://components/stats_component.gd")
const ModifierNodeScript := preload("res://components/stat_modifier_node.gd")

var stats: StatsComponent


class FakeModifier extends StatModifierNode:
	var mods: Array[StatModifierData] = []

	func get_modifiers() -> Array[StatModifierData]:
		return mods


func before_each() -> void:
	stats = StatsScript.new()
	add_child_autofree(stats)


func test_devuelve_valores_base_sin_modificadores() -> void:
	stats.base_max_speed = 200.0
	stats.mark_dirty()
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 200.0, 0.01)


func test_modificador_aditivo_suma_al_base() -> void:
	stats.base_max_speed = 200.0
	var mod := FakeModifier.new()
	mod.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 50.0, 1.0)]
	stats.add_child(mod)

	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 250.0, 0.01)


func test_modificador_multiplicativo_se_aplica_tras_la_suma() -> void:
	stats.base_max_speed = 200.0
	var mod := FakeModifier.new()
	mod.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 50.0, 2.0)]
	stats.add_child(mod)

	# (200 + 50) * 2 = 500
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 500.0, 0.01)


func test_varios_modificadores_se_acumulan() -> void:
	stats.base_max_speed = 100.0
	var a := FakeModifier.new()
	a.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 20.0, 1.0)]
	var b := FakeModifier.new()
	b.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 30.0, 1.5)]
	stats.add_child(a)
	stats.add_child(b)

	# (100 + 20 + 30) * 1.5 = 225
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 225.0, 0.01)


func test_retirar_el_modificador_restaura_el_base() -> void:
	stats.base_max_speed = 200.0
	var mod := FakeModifier.new()
	mod.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 100.0, 1.0)]
	stats.add_child(mod)
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 300.0, 0.01)

	stats.remove_child(mod)
	mod.free()
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 200.0, 0.01,
			"al retirar el power-up el stat vuelve a su base")


func test_los_booleanos_se_leen_como_umbral() -> void:
	stats.base_is_immovable = false
	stats.mark_dirty()
	assert_false(stats.get_stat_bool(StatsComponent.StatID.IS_IMMOVABLE))

	stats.base_is_immovable = true
	stats.mark_dirty()
	assert_true(stats.get_stat_bool(StatsComponent.StatID.IS_IMMOVABLE))


func test_air_jumps_se_lee_como_entero() -> void:
	stats.base_air_jumps = 0.0
	var mod := FakeModifier.new()
	mod.mods = [StatModifierData.new(StatsComponent.StatID.AIR_JUMPS, 1.0, 1.0)]
	stats.add_child(mod)

	assert_eq(stats.get_stat_int(StatsComponent.StatID.AIR_JUMPS), 1,
			"desbloquear el doble salto es añadir un modificador")


func test_la_senal_del_modificador_invalida_la_cache() -> void:
	stats.base_max_speed = 100.0
	var mod := FakeModifier.new()
	mod.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 0.0, 1.0)]
	stats.add_child(mod)
	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 100.0, 0.01)

	mod.mods = [StatModifierData.new(StatsComponent.StatID.MAX_SPEED, 400.0, 1.0)]
	mod.modifier_changed.emit()

	assert_almost_eq(stats.get_stat(StatsComponent.StatID.MAX_SPEED), 500.0, 0.01,
			"emitir modifier_changed debe forzar el recálculo")
