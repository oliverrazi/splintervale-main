extends Node

signal quest_added(quest_id: String)
signal quest_updated(quest_id: String, current: int, target: int)
signal quest_completed(quest_id: String)
signal quest_turned_in(quest_id: String)

# Alle verfügbaren Quests (aus Resources geladen)
var _quest_database: Dictionary = {}  # quest_id -> QuestData

# Aktive Quest-Zustände
var _active_quests: Dictionary = {}  # quest_id -> QuestState
var _completed_quests: Array[String] = []
var _turned_in_quests: Array[String] = []

# Gesammelte/Interagierte Objekte in der Welt
var _collected_world_objects: Array[String] = []  # Unique IDs


class QuestState:
	var quest_id: String = ""
	var current_amount: int = 0
	var is_complete: bool = false
	
	func _init(id: String) -> void:
		quest_id = id
		current_amount = 0
		is_complete = false
	
	func to_dict() -> Dictionary:
		return {
			"quest_id": quest_id,
			"current_amount": current_amount,
			"is_complete": is_complete
		}
	
	static func from_dict(data: Dictionary) -> QuestState:
		var state := QuestState.new(data.get("quest_id", ""))
		state.current_amount = data.get("current_amount", 0)
		state.is_complete = data.get("is_complete", false)
		return state


func _ready() -> void:
	_load_quest_database()


func _load_quest_database() -> void:
	var quest_dir := "res://data/quest/"
	var dir := DirAccess.open(quest_dir)
	
	if dir == null:
		DirAccess.make_dir_recursive_absolute(quest_dir)
		return

	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var full_path := quest_dir + file_name

			var quest: Resource = load(full_path)

			
			if quest is QuestData:
				var quest_data: QuestData = quest as QuestData

				
				if quest_data.quest_id != "":
					_quest_database[quest_data.quest_id] = quest_data
				else:
					print("WARNING: Quest has empty ID!")
			else:
				print("WARNING: Resource is not QuestData!")
		
		file_name = dir.get_next()
	
	dir.list_dir_end()


# === QUEST MANAGEMENT ===

func add_quest(quest_id: String) -> bool:
	if has_quest(quest_id):
		print("Quest already active: ", quest_id)
		return false
	
	if is_quest_turned_in(quest_id):
		print("Quest already turned in: ", quest_id)
		return false
	
	var quest_data: QuestData = _quest_database.get(quest_id)
	if quest_data == null:
		push_warning("Quest not found in database: ", quest_id)
		# Trotzdem hinzufügen (für dynamische Quests)
	
	var state := QuestState.new(quest_id)
	_active_quests[quest_id] = state
	
	print("Quest added: ", quest_id)
	quest_added.emit(quest_id)
	
	return true


func has_quest(quest_id: String) -> bool:
	return _active_quests.has(quest_id)


func is_quest_complete(quest_id: String) -> bool:
	if _completed_quests.has(quest_id):
		return true
	
	var state: QuestState = _active_quests.get(quest_id)
	if state:
		return state.is_complete
	
	return false


func is_quest_turned_in(quest_id: String) -> bool:
	return _turned_in_quests.has(quest_id)


func get_quest_data(quest_id: String) -> QuestData:
	return _quest_database.get(quest_id)


func get_quest_state(quest_id: String) -> QuestState:
	return _active_quests.get(quest_id)


func get_active_quests() -> Array[String]:
	var quests: Array[String] = []
	for quest_id in _active_quests.keys():
		quests.append(quest_id)
	return quests


func get_completed_quests() -> Array[String]:
	return _completed_quests.duplicate()


# === QUEST PROGRESS ===

func update_quest_progress(quest_id: String, amount: int = 1) -> void:
	var state: QuestState = _active_quests.get(quest_id)
	if state == null:
		return
	
	var quest_data: QuestData = _quest_database.get(quest_id)
	var target: int = quest_data.target_amount if quest_data else 1
	
	state.current_amount += amount
	
	quest_updated.emit(quest_id, state.current_amount, target)
	
	if state.current_amount >= target:
		_complete_quest(quest_id)


func set_quest_progress(quest_id: String, amount: int) -> void:
	var state: QuestState = _active_quests.get(quest_id)
	if state == null:
		return
	
	var quest_data: QuestData = _quest_database.get(quest_id)
	var target: int = quest_data.target_amount if quest_data else 1
	
	state.current_amount = amount
	
	quest_updated.emit(quest_id, state.current_amount, target)
	
	if state.current_amount >= target:
		_complete_quest(quest_id)


func _complete_quest(quest_id: String) -> void:
	var state: QuestState = _active_quests.get(quest_id)
	if state == null or state.is_complete:
		return
	
	state.is_complete = true
	
	if quest_id not in _completed_quests:
		_completed_quests.append(quest_id)
	
	print("Quest completed: ", quest_id)
	quest_completed.emit(quest_id)


func turn_in_quest(quest_id: String) -> bool:
	if not is_quest_complete(quest_id):
		return false
	
	var quest_data: QuestData = _quest_database.get(quest_id)
	
	# Rewards geben
	if quest_data:
		if quest_data.reward_exp > 0:
			GameManager.player_data.add_exp(quest_data.reward_exp)
		if quest_data.reward_gold > 0:
			GameManager.player_data.gold += quest_data.reward_gold
			GameManager.player_data.gold_changed.emit(GameManager.player_data.gold)
		# TODO: Items hinzufügen
	
	# Quest abschließen
	_active_quests.erase(quest_id)
	
	if quest_id not in _turned_in_quests:
		_turned_in_quests.append(quest_id)
	
	print("Quest turned in: ", quest_id)
	quest_turned_in.emit(quest_id)
	
	return true


# === WORLD OBJECTS ===

func collect_world_object(object_id: String, quest_id: String = "") -> void:
	if object_id in _collected_world_objects:
		return
	
	_collected_world_objects.append(object_id)
	print("World object collected: ", object_id)
	
	# Quest Progress updaten falls angegeben
	if quest_id != "" and has_quest(quest_id):
		update_quest_progress(quest_id)


func is_world_object_collected(object_id: String) -> bool:
	return object_id in _collected_world_objects


# === CONDITIONS ===

func check_condition(condition: String) -> bool:
	"""
	Prüft Bedingungen wie:
	- "level:5" - Player Level >= 5
	- "quest_active:find_bag" - Quest ist aktiv
	- "quest_complete:find_bag" - Quest ist abgeschlossen
	- "quest_turned_in:find_bag" - Quest wurde abgegeben
	- "has_item:key_01" - Spieler hat Item
	- "gold:100" - Spieler hat >= 100 Gold
	- "flag:talked_to_elder" - Flag ist gesetzt
	- "!quest_active:find_bag" - Quest ist NICHT aktiv (Negation mit !)
	"""
	condition = condition.strip_edges()
	condition = condition.replace('"', '')
	condition = condition.replace("'", '')
	
	if condition == "":
		return true
	
	# Multiple Conditions mit Komma
	if "," in condition:
		var conditions: PackedStringArray = condition.split(",")
		for cond in conditions:
			var clean_cond: String = cond.strip_edges()
			if not _check_single_condition(clean_cond):
				return false
		return true
	
	return _check_single_condition(condition)

func _check_single_condition(condition: String) -> bool:
	if condition == "":
		return true
	
	# ZUERST alle Anführungszeichen und Whitespace entfernen
	condition = condition.strip_edges()
	condition = condition.replace('"', '')
	condition = condition.replace("'", '')
	
	if condition == "":
		return true
	
	# DANN auf Negation prüfen
	var negated: bool = condition.begins_with("!")
	if negated:
		condition = condition.substr(1)
	
	var parts: PackedStringArray = condition.split(":")
	
	if parts.size() < 2:
		return not negated
	
	var type: String = parts[0].strip_edges()
	var value: String = parts[1].strip_edges()
	var result: bool = false
	
	match type:
		"level":
			var required_level: int = int(value)
			result = GameManager.player_data.level >= required_level
			print("Level check: ", GameManager.player_data.level, " >= ", required_level, " = ", result)
		
		"quest_active":
			result = has_quest(value)
			print("Quest active check: ", value, " = ", result)
		
		"quest_complete":
			result = is_quest_complete(value)
			print("Quest complete check: ", value, " = ", result)
		
		"quest_turned_in":
			result = is_quest_turned_in(value)
			print("Quest turned in check: ", value, " = ", result)
		
		"gold":
			var required_gold: int = int(value)
			result = GameManager.player_data.gold >= required_gold
			print("Gold check: ", GameManager.player_data.gold, " >= ", required_gold, " = ", result)
		
		"flag":
			if GameManager.has_method("get_flag"):
				result = GameManager.get_flag(value)
			else:
				result = false
			print("Flag check: ", value, " = ", result)
		
		"has_item":
			var inv_manager: Node = get_node_or_null("/root/InventoryManager")
			if inv_manager:
				result = inv_manager.has_item(value)
			else:
				result = false
			print("Has item check: ", value, " = ", result)
		
		_:
			print("Unknown type: '", type, "', defaulting to true")
			result = true
	
	var final_result: bool = result if not negated else not result
	print("Final result (negated=", negated, "): ", final_result)
	print("=== END CHECK ===")
	
	return final_result

# === SAVE / LOAD ===

func get_save_data() -> Dictionary:
	var active_quest_data: Array[Dictionary] = []
	for quest_id in _active_quests:
		var state: QuestState = _active_quests[quest_id]
		active_quest_data.append(state.to_dict())
	
	return {
		"active_quests": active_quest_data,
		"completed_quests": _completed_quests.duplicate(),
		"turned_in_quests": _turned_in_quests.duplicate(),
		"collected_world_objects": _collected_world_objects.duplicate()
	}


func load_save_data(data: Dictionary) -> void:
	_active_quests.clear()
	_completed_quests.clear()
	_turned_in_quests.clear()
	_collected_world_objects.clear()
	
	var active_quest_data: Array = data.get("active_quests", [])
	for quest_data in active_quest_data:
		var state := QuestState.from_dict(quest_data)
		_active_quests[state.quest_id] = state
	
	var completed: Array = data.get("completed_quests", [])
	for quest_id in completed:
		_completed_quests.append(quest_id)
	
	var turned_in: Array = data.get("turned_in_quests", [])
	for quest_id in turned_in:
		_turned_in_quests.append(quest_id)
	
	var collected: Array = data.get("collected_world_objects", [])
	for object_id in collected:
		_collected_world_objects.append(object_id)
	
	print("Quest data loaded - Active: ", _active_quests.size(), ", Completed: ", _completed_quests.size())
