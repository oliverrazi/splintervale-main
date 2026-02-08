@tool
extends Node3D
class_name FenceManager

## FenceManager - Container für alle Zäune
## Wähle dieses Node aus um den Fence Builder zu aktivieren

@export_group("Fence Scenes")
@export var fence_scene_1: PackedScene
@export var fence_scene_1_length: float = 2.0
@export var fence_scene_2: PackedScene
@export var fence_scene_2_length: float = 2.0
@export var fence_scene_3: PackedScene
@export var fence_scene_3_length: float = 2.5

@export_group("Settings")
@export var gap_size: float = 0.0
@export var random_gap_chance: float = 0.0
@export var height_offset: float = 0.0
## Maximale zufällige Rotation in Grad (z.B. 5 = -5° bis +5°)
@export var random_rotation_range: float = 5.0

func get_fence_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	if fence_scene_1 != null:
		scenes.append(fence_scene_1)
	if fence_scene_2 != null:
		scenes.append(fence_scene_2)
	if fence_scene_3 != null:
		scenes.append(fence_scene_3)
	return scenes

func get_fence_lengths() -> Array[float]:
	var lengths: Array[float] = []
	if fence_scene_1 != null:
		lengths.append(fence_scene_1_length)
	if fence_scene_2 != null:
		lengths.append(fence_scene_2_length)
	if fence_scene_3 != null:
		lengths.append(fence_scene_3_length)
	return lengths

func get_fence_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	if fence_scene_1 != null:
		data.append({"scene": fence_scene_1, "length": fence_scene_1_length})
	if fence_scene_2 != null:
		data.append({"scene": fence_scene_2, "length": fence_scene_2_length})
	if fence_scene_3 != null:
		data.append({"scene": fence_scene_3, "length": fence_scene_3_length})
	return data

func get_fence_count() -> int:
	var count = 0
	for child in get_children():
		if child.has_meta("is_fence"):
			count += 1
	return count
