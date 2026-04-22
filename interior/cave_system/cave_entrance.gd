class_name CaveEntrance
extends Area3D

@export_file("*.tscn") var target_scene: String
@export var spawn_point_id: String = ""

var _triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true

	# Direkt am PlayerManager setzen
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").pending_spawn_id = spawn_point_id

	SceneTransition.transition_to(target_scene)
