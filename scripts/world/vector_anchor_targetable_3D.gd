extends StaticBody3D
class_name VectorAnchorTargetable3D

## Basisklasse für statische Vector-Anchor-Ziele (Bollards, Anker-Ringe, etc.)

@export var anchor_point_path: NodePath = "AnchorPoint"
@export var indicator_point_path: NodePath = "IndicatorPoint"

@export var chainable: bool = true


func _ready() -> void:
	add_to_group("targetable")

func get_vector_anchor_anchor_position() -> Vector3:
	var p := get_node_or_null(anchor_point_path) as Node3D
	if p != null:
		return p.global_position
	return global_position


func get_vector_anchor_indicator_position() -> Vector3:
	var p := get_node_or_null(indicator_point_path) as Node3D
	if p != null:
		return p.global_position
	return get_vector_anchor_anchor_position()


func is_vector_anchor_targetable() -> bool:
	return true
	

func is_vector_anchor_chainable() -> bool:
	return chainable
