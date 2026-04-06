extends Node3D
class_name TreasureChest

signal chest_opened(chest_id: String)

@export_group("Chest Setup")
@export var chest_id: String = "chest_001"  # Unique ID für Save-System
@export var lid_node_path: NodePath = "Lid"  # Pfad zum Deckel-Node

@export_group("Lid Animation")
@export var lid_open_angle: float = -110.0  # Grad (negativ = nach hinten kippen)
@export var lid_open_duration: float = 0.6
@export var lid_rotation_axis: String = "x"  # "x" oder "z" je nach Model-Orientierung

@export_group("Interaction")
@export var interaction_prompt: String = "Open"

@export_group("Loot")
@export var loot_entries: Array[ChestLootEntry] = []
# Format: [{"item_id": "potion_hp", "amount": 1}, {"item_id": "gold_coin", "amount": 5}]

var is_opened: bool = false

var _player_in_range: bool = false
var _lid: Node3D = null
var _lid_closed_rotation: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("treasure_chest")
	
	# Deckel referenzieren
	if lid_node_path:
		_lid = get_node_or_null(lid_node_path)
	
	if _lid:
		_lid_closed_rotation = _lid.rotation_degrees
		
	var interaction_area: Area3D = $InteractionArea
	if interaction_area:
		interaction_area.body_entered.connect(_on_interaction_area_body_entered)
		interaction_area.body_exited.connect(_on_interaction_area_body_exited)
	else:
		push_warning("TreasureChest: InteractionArea node not found!")
	
	# Prüfen ob bereits geöffnet (über GameManager Flags)
	if _is_already_opened():
		_set_opened_instant()


# ============ INTERACTION ============

func can_interact() -> bool:
	return _player_in_range and not is_opened


func interact() -> void:
	if not can_interact():
		return
	
	open_chest()


func open_chest() -> void:
	if is_opened:
		return
	
	is_opened = true
	
	_save_opened_flag()
	_animate_lid_open()
	chest_opened.emit(chest_id)
	
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_frozen"):
		player.set_frozen(true)
	
	# Loot verteilen (nach kurzer Verzögerung für die Animation)
	if not loot_entries.is_empty():
		_give_loot_and_unfreeze(player)
	else:
		# Kein Loot — nach Animation freigeben
		await get_tree().create_timer(lid_open_duration).timeout
		_unfreeze_player(player)


# ============ LID ANIMATION ============

func _animate_lid_open() -> void:
	if _lid == null:
		push_warning("TreasureChest: No lid node found at path: ", lid_node_path)
		return
	
	var target_rotation: Vector3 = _lid_closed_rotation
	match lid_rotation_axis:
		"x":
			target_rotation.x = lid_open_angle
		"z":
			target_rotation.z = lid_open_angle
	
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)  # Leichtes Überschwingen für natürliches Gefühl
	tween.tween_property(_lid, "rotation_degrees", target_rotation, lid_open_duration)


func _set_opened_instant() -> void:
	"""Setzt Kiste sofort auf offen (für Save-Load)"""
	is_opened = true
	
	if _lid:
		var target_rotation: Vector3 = _lid_closed_rotation
		match lid_rotation_axis:
			"x":
				target_rotation.x = lid_open_angle
			"z":
				target_rotation.z = lid_open_angle
		_lid.rotation_degrees = target_rotation


# ============ LOOT ============

func _give_loot_and_unfreeze(player: Node3D) -> void:
	# Warte bis Deckel offen ist
	await get_tree().create_timer(lid_open_duration * 0.5).timeout
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		_unfreeze_player(player)
		return
	
	# Items nacheinander geben (jedes wartet auf pickup_finished)
	for entry in loot_entries:
		if entry == null or entry.item_id == "":
			continue
		
		inv_manager.add_item(entry.item_id, entry.amount, true, entry.custom_text)
		
		# Warten bis der Pickup-Dialog für dieses Item geschlossen wurde
		if inv_manager.has_signal("item_pickup_finished"):
			await inv_manager.item_pickup_finished
	
	# Alles eingesammelt — Player freigeben
	_unfreeze_player(player)

func _unfreeze_player(player: Node3D) -> void:
	if player and is_instance_valid(player) and player.has_method("set_frozen"):
		player.set_frozen(false)

# ============ SAVE / LOAD ============

func _is_already_opened() -> bool:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_flag"):
		return game_manager.get_flag("chest_opened_" + chest_id)
	return false


func _save_opened_flag() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("set_flag"):
		game_manager.set_flag("chest_opened_" + chest_id, true)


# ============ DETECTION ============

func _on_interaction_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		# Player informieren
		if body.has_method("_set_nearby_chest"):
			body._set_nearby_chest(self)


func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if body.has_method("_set_nearby_chest"):
			body._set_nearby_chest(null)
