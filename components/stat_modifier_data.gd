class_name StatModifierData
extends RefCounted

var stat_id: int
var add_value: float = 0.0
var mult_value: float = 1.0

func _init(p_stat_id: int = -1, p_add: float = 0.0, p_mult: float = 1.0) -> void:
	stat_id = p_stat_id
	add_value = p_add
	mult_value = p_mult
