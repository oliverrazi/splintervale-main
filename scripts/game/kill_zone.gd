extends Area3D
class_name KillZone



func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is Enemy:
		(body as Enemy).start_drowning()
	elif body.is_in_group("player") and body.has_method("respawn_after_fall"):
		body.respawn_after_fall()
