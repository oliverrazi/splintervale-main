# MusicZone.gd
class_name MusicZone
extends Area3D

@export var music_track: AudioStream
@export var crossfade_duration: float = 2.0
@export var zone_priority: int = 0  # höher = wichtiger (für überlappende Zonen)

func _ready() -> void:
	#body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		MusicManager.enter_zone(self)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		MusicManager.exit_zone(self)
