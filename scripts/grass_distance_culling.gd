extends Node3D

var grass = []
var current_grass

var first_frame  = true

@export var grass_cull_distance = 50

func _ready():
	for _i in self.get_children():
		grass.append(_i)
		print (_i)
		



func _on_lod_timer_timeout() -> void:
#func _process(delta: float) -> void:
	var camera_pos

	if Engine.is_editor_hint():
			camera_pos = EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
	else:
			camera_pos = get_viewport().get_camera_3d().global_position

	var camera_distance = global_position.distance_to(camera_pos)

	for a in grass:
		var distance_to_grass = camera_pos.distance_to(a.global_transform.origin)
		#print(distance_to_grass)

		if distance_to_grass > grass_cull_distance:
			a.visible = false
		else:
			a.visible = true
