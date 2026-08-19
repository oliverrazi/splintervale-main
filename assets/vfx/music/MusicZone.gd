class_name MusicZone
extends Area3D

@export var music_track: AudioStream
@export var crossfade_duration: float = 2.0
@export var zone_priority: int = 0

## Optionaler Kontext-Key. Zonen mit demselben music_context teilen sich
## einen Owner im MusicManager — dadurch läuft die Musik szenenübergreifend
## weiter, wenn zusammenhängende Abschnitte denselben Kontext nutzen.
## Leer = jede Zone ist ihr eigener Owner (altes Verhalten).
@export var music_context: String = ""

var _owner_key: String


func _ready() -> void:
	if music_context.is_empty():
		_owner_key = "zone:%d" % get_instance_id()
	else:
		_owner_key = "ctx:" + music_context
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		MusicManager.push_music(_owner_key, music_track, zone_priority, crossfade_duration)


func _on_body_exited(body: Node3D) -> void:
	# Nur poppen, wenn der Spieler die Zone WÄHREND des Spiels verlässt —
	# nicht, wenn die Zone durch einen Szenenwechsel gefreed wird.
	if not is_inside_tree() or get_tree() == null:
		return
	if body.is_in_group("player"):
		MusicManager.pop_music(_owner_key, crossfade_duration)
