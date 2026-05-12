extends Node3D

# Ziehe hier deinen MeshInstance3D-Node rein
@export var mesh_node: Node3D

# Wie viele Richtungen (8 = alle 45°, 4 = nur N/S/O/W)
@export var direction_count: int = 8

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or not mesh_node:
		return

	# Richtungsvektor von Oger zur Kamera, nur horizontal
	var dir := camera.global_position - global_position
	dir.y = 0.0

	# Nichts tun wenn Kamera direkt über/unter dem Oger ist
	if dir.length_squared() < 0.001:
		return

	dir = dir.normalized()

	# Winkel berechnen
	var angle := atan2(dir.x, dir.z)

	# Auf gewählte Richtungsanzahl einrasten
	var step := TAU / float(direction_count)
	var snapped_angle : Variant= round(angle / step) * step

	# Nur auf das Mesh anwenden, nicht den ganzen CharacterBody
	mesh_node.rotation.y = snapped_angle
