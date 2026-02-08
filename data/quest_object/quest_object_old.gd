extends Area3D
class_name QuestObjectOld

@export var object_id: String = ""  # Unique ID
@export var related_quest_id: String = ""  # Quest die aktualisiert wird
@export var pickup_text: String = "Pick up"
@export var auto_pickup: bool = true  # Automatisch aufheben oder Interact?

var _collected: bool = false


func _ready() -> void:
	add_to_group("quest_object")
	
	# Prüfen ob bereits gesammelt
	if QuestManager.is_world_object_collected(object_id):
		queue_free()
		return
	
	if auto_pickup:
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _collected:
		collect()


func collect() -> void:
	if _collected:
		return
	
	_collected = true
	
	QuestManager.collect_world_object(object_id, related_quest_id)
	
	# Optional: Pickup VFX/Sound
	
	queue_free()


func can_interact() -> bool:
	return not _collected and not auto_pickup


func interact() -> void:
	collect()
