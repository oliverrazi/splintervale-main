## CaveExit — Trigger that returns the player from a cave to the overworld.
##
## Place this as an Area3D at cave exit points. When the player enters,
## it triggers a fade-to-black and returns to the overworld at the
## position stored in GlobalCaveData.

class_name CaveExit
extends Area3D

@export var exit_id: String = "exit_default"
## Override return position. If zero, uses GlobalCaveData.return_position.
@export var override_return_position: Vector3 = Vector3.ZERO
## Override return scene. If empty, uses GlobalCaveData.return_scene_path.
@export_file("*.tscn") var override_return_scene: String = ""
## If true, player must press interact to exit. Otherwise auto-exit on overlap.
@export var require_interaction: bool = true

var _player_inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Player layer
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not require_interaction:
		return
	if _player_inside and event.is_action_pressed("interact"):
		_trigger_exit()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	if not require_interaction:
		_trigger_exit()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _trigger_exit() -> void:
	# Override return data if configured
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	if cave_data:
		if not override_return_scene.is_empty():
			cave_data.return_scene_path = override_return_scene
		if override_return_position != Vector3.ZERO:
			cave_data.return_position = override_return_position

	# Find the CaveSystem parent and tell it to exit
	var node := get_parent()
	while node:
		if node is CaveSystem:
			node.exit_cave()
			return
		node = node.get_parent()

	push_error("CaveExit: Could not find CaveSystem parent node!")
