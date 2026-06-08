extends Node3D
class_name TreasureChest

signal chest_opened(chest_id: String)

@export_group("Chest Setup")
@export var chest_id: String = "chest_001"
@export var lid_node_path: NodePath = "Lid"

@export_group("Lid Animation")
@export var lid_open_angle: float = -110.0
@export var lid_open_duration: float = 0.6
@export var lid_rotation_axis: String = "x"

@export_group("Interaction")
@export var interaction_prompt: String = "Open"

@export_group("Loot")
@export var loot_entries: Array[ChestLootEntry] = []

@export_group("Reveal")
## Wenn nicht leer: Truhe ist initial unsichtbar UND ohne Collision bis dieser
## GameManager-Flag gesetzt ist. Pattern: Boss-Truhen mit "boss_defeated_<boss_id>".
@export var reveal_flag: String = ""
## Fade-in Dauer beim dynamischen Reveal.
@export var reveal_fade_duration: float = 0.8

var is_opened: bool = false
var _is_revealed: bool = true

var _player_in_range: bool = false
var _lid: Node3D = null
var _lid_closed_rotation: Vector3 = Vector3.ZERO
@onready var _interaction_area: Area3D = $InteractionArea


func _ready() -> void:
	add_to_group("treasure_chest")
	
	if lid_node_path:
		_lid = get_node_or_null(lid_node_path)
	if _lid:
		_lid_closed_rotation = _lid.rotation_degrees
	
	if _interaction_area:
		_interaction_area.body_entered.connect(_on_interaction_area_body_entered)
		_interaction_area.body_exited.connect(_on_interaction_area_body_exited)
	else:
		push_warning("TreasureChest: InteractionArea node not found!")
	
	# === REVEAL STATE INITIALISIEREN ===
	if reveal_flag != "":
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("get_flag") and gm.get_flag(reveal_flag):
			_set_revealed_instant()
		else:
			_hide_for_reveal()
	
	if _is_already_opened():
		_set_opened_instant()


# ============ REVEAL ============

func _hide_for_reveal() -> void:
	_is_revealed = false
	visible = false
	
	# Alle Meshes auf voll transparent vorbereiten - so ist der Reveal smooth
	for m in find_children("*", "GeometryInstance3D", true, false):
		var geom := m as GeometryInstance3D
		if geom:
			geom.transparency = 1.0
	
	# Physische Collision deaktivieren - Spieler soll nicht gegen eine
	# unsichtbare Truhe laufen
	_set_collision_enabled(false)
	
	if _interaction_area:
		_interaction_area.monitoring = false


func _set_revealed_instant() -> void:
	_is_revealed = true
	visible = true
	for m in find_children("*", "GeometryInstance3D", true, false):
		var geom := m as GeometryInstance3D
		if geom:
			geom.transparency = 0.0
	_set_collision_enabled(true)
	if _interaction_area:
		_interaction_area.monitoring = true


## Wird vom ChestReveal aufgerufen. Truhe fadet rein via transparency-Tween.
func reveal_with_animation() -> void:
	if _is_revealed:
		return
	_is_revealed = true
	
	if reveal_flag != "":
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("set_flag"):
			gm.set_flag(reveal_flag, true)
	
	visible = true
	
	# Collision sofort wieder aktivieren - sobald die Truhe materialisiert,
	# ist sie solide
	_set_collision_enabled(true)
	
	var meshes := find_children("*", "GeometryInstance3D", true, false)
	var tw := create_tween().set_parallel()
	
	for m in meshes:
		var geom := m as GeometryInstance3D
		if geom == null:
			continue
		geom.transparency = 1.0
		tw.tween_property(geom, "transparency", 0.0, reveal_fade_duration) \
			.set_ease(Tween.EASE_OUT)
	
	tw.chain().tween_callback(_enable_interaction_after_reveal)


func _enable_interaction_after_reveal() -> void:
	if _interaction_area:
		_interaction_area.monitoring = true


## Aktiviert/deaktiviert alle CollisionShape3D der Truhe.
## set_deferred, weil Collision-Aenderungen im Physics-Step sonst Fehler werfen.
func _set_collision_enabled(enabled: bool) -> void:
	for cs in find_children("*", "CollisionShape3D", true, false):
		var shape := cs as CollisionShape3D
		if shape:
			shape.set_deferred("disabled", not enabled)


# ============ INTERACTION ============

func can_interact() -> bool:
	return _player_in_range and not is_opened and _is_revealed


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
	
	if not loot_entries.is_empty():
		_give_loot_and_unfreeze(player)
	else:
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
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(_lid, "rotation_degrees", target_rotation, lid_open_duration)


func _set_opened_instant() -> void:
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
	await get_tree().create_timer(lid_open_duration * 0.5).timeout
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		_unfreeze_player(player)
		return
	
	for entry in loot_entries:
		if entry == null or entry.item_id == "":
			continue
		
		inv_manager.add_item(entry.item_id, entry.amount, true, entry.custom_text)
		
		if inv_manager.has_signal("item_pickup_finished"):
			await inv_manager.item_pickup_finished
	
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
		if body.has_method("_set_nearby_chest"):
			body._set_nearby_chest(self)


func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if body.has_method("_set_nearby_chest"):
			body._set_nearby_chest(null)
