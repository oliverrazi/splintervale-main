extends Node3D

@export var rotation_speed: float = -0.05  # Umdrehungen pro Sekunde

func _process(delta: float) -> void:
	rotate_z(TAU * rotation_speed * delta)
