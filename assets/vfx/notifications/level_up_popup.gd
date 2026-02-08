extends Node3D

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var label: Label3D = $Label3D

func play(text: String = "Level up!") -> void:
	label.text = text
	anim.play("pop")
	# Wenn Animation fertig: automatisch entfernen
	anim.animation_finished.connect(_on_anim_finished, CONNECT_ONE_SHOT)

func _on_anim_finished(_name: StringName) -> void:
	queue_free()
