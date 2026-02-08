extends Node

signal inventory_changed
signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal item_used(item_id: String)
signal hotbar_changed(slot_index: int, item_id: String)

signal item_pickup_started(item_id: String)
signal item_pickup_finished(item_id: String)

var pickup_effect_scene: PackedScene = null

# Item Database
var _item_database: Dictionary = {}  # item_id -> ItemData

# Inventar: item_id -> amount
var _inventory: Dictionary = {}

# Hotbar Slots (W, A, S, D) -> item_id
var _hotbar: Array[String] = ["", "", "", ""]

const HOTBAR_SLOT_W: int = 0
const HOTBAR_SLOT_A: int = 1
const HOTBAR_SLOT_S: int = 2
const HOTBAR_SLOT_D: int = 3


func _ready() -> void:
	_load_item_database()
	

	if _inventory.is_empty():
		add_item("sword1", 1)
		assign_to_hotbar(HOTBAR_SLOT_W, "sword1")
		#add_item("shift_boots", 1)
	
		add_item("health_potion1", 3)
	
	
	var effect_path: String = "res://assets/vfx/itempickup/item_pickup_effect.tscn"
	if ResourceLoader.exists(effect_path):
		print("DRIN")	
		pickup_effect_scene = load(effect_path)


func _load_item_database() -> void:
	var item_dirs: Array[String] = [
		"res://Data/Items/",
		"res://Resources/Items/"
	]
	
	for item_dir in item_dirs:
		var dir := DirAccess.open(item_dir)
		if dir == null:
			continue
		
		print("Loading items from: ", item_dir)
		
		dir.list_dir_begin()
		var file_name := dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var full_path := item_dir + file_name
				var item: Resource = load(full_path)
				
				if item is ItemData:
					var item_data: ItemData = item as ItemData
					if item_data.item_id != "":
						_item_database[item_data.item_id] = item_data			
			file_name = dir.get_next()
		
		dir.list_dir_end()


# === ITEM DATABASE ===

func get_item_data(item_id: String) -> ItemData:
	return _item_database.get(item_id)


func register_item(item_data: ItemData) -> void:
	if item_data and item_data.item_id != "":
		_item_database[item_data.item_id] = item_data


# === INVENTORY MANAGEMENT ===

func add_item(item_id: String, amount: int = 1, show_effect: bool = false, custom_pickup_text: String = "") -> bool:
	if amount <= 0:
		return false
	
	var item_data: ItemData = get_item_data(item_id)
	
	if _inventory.has(item_id):
		var current: int = _inventory[item_id]
		var max_stack: int = item_data.max_stack if item_data else 99
		_inventory[item_id] = min(current + amount, max_stack)
	else:
		_inventory[item_id] = amount
	
	print("Added item: ", item_id, " x", amount, " (total: ", _inventory[item_id], ")")
	
	item_added.emit(item_id, amount)
	inventory_changed.emit()
	
	if show_effect and item_data.icon:
		print("SHOW PICKUP DIALOGUE")
		_show_pickup_dialogue(item_data, custom_pickup_text)
	
	return true


func remove_item(item_id: String, amount: int = 1) -> bool:
	if not _inventory.has(item_id):
		return false
	
	var current: int = _inventory[item_id]
	
	if current < amount:
		return false
	
	_inventory[item_id] = current - amount
	
	if _inventory[item_id] <= 0:
		_inventory.erase(item_id)
		
		# Aus Hotbar entfernen wenn leer
		for i in range(_hotbar.size()):
			if _hotbar[i] == item_id:
				_hotbar[i] = ""
				hotbar_changed.emit(i, "")
	
	print("Removed item: ", item_id, " x", amount)
	
	item_removed.emit(item_id, amount)
	inventory_changed.emit()
	
	return true


func has_item(item_id: String, amount: int = 1) -> bool:
	if not _inventory.has(item_id):
		return false
	return _inventory[item_id] >= amount


func get_item_count(item_id: String) -> int:
	return _inventory.get(item_id, 0)


func get_all_items() -> Dictionary:
	return _inventory.duplicate()


# === HOTBAR ===

func assign_to_hotbar(slot_index: int, item_id: String, remove_from_other_slots: bool = false) -> bool:
	if slot_index < 0 or slot_index >= _hotbar.size():
		return false
	
	# Prüfen ob Item im Inventar
	if item_id != "" and not has_item(item_id):
		return false
	
	# Nur wenn explizit gewünscht: Item aus anderen Slots entfernen
	if remove_from_other_slots:
		for i in range(_hotbar.size()):
			if _hotbar[i] == item_id and i != slot_index:
				_hotbar[i] = ""
				hotbar_changed.emit(i, "")
	
	_hotbar[slot_index] = item_id
	
	print("Hotbar slot ", slot_index, " = ", item_id)
	
	hotbar_changed.emit(slot_index, item_id)
	
	return true


func get_hotbar_item(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= _hotbar.size():
		return ""
	return _hotbar[slot_index]


func get_hotbar_item_data(slot_index: int) -> ItemData:
	var item_id: String = get_hotbar_item(slot_index)
	if item_id == "":
		return null
	return get_item_data(item_id)


func get_hotbar() -> Array[String]:
	return _hotbar.duplicate()


func clear_hotbar_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _hotbar.size():
		_hotbar[slot_index] = ""
		hotbar_changed.emit(slot_index, "")


# === ITEM USAGE ===

func use_item(item_id: String) -> bool:
	var item_data: ItemData = get_item_data(item_id)
	
	if item_data == null:
		print("Item not found: ", item_id)
		return false
	
	if not item_data.usable:
		print("Item not usable: ", item_id)
		return false
	
	if not has_item(item_id):
		print("Item not in inventory: ", item_id)
		return false
	
	# Effekte anwenden
	_apply_item_effects(item_data)
	
	# Verbrauchen wenn consumable
	if item_data.consumable:
		remove_item(item_id, 1)
	
	item_used.emit(item_id)
	
	return true


func use_hotbar_slot(slot_index: int) -> bool:
	var item_id: String = get_hotbar_item(slot_index)
	if item_id == "":
		return false
	return use_item(item_id)


func _apply_item_effects(item_data: ItemData) -> void:
	if item_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data if GameManager else null
	if pd == null:
		return
	
	# Heilung
	if item_data.heal_amount > 0:
		pd.heal(item_data.heal_amount)
		print("Healed for ", item_data.heal_amount)
	
	# Stamina
	if item_data.stamina_restore > 0:
		pd.restore_stamina(item_data.stamina_restore)
		print("Restored ", item_data.stamina_restore, " stamina")
	
	# Custom Effect Action
	if item_data.effect_action != "":
		_execute_effect_action(item_data.effect_action)


func _execute_effect_action(action: String) -> void:
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return
	
	var type: String = parts[0]
	
	match type:
		"buff":
			# buff:attack:10:30 -> +10 attack für 30 Sekunden
			if parts.size() >= 4:
				var buff_type: String = parts[1]
				var amount: int = int(parts[2])
				var duration: float = float(parts[3])
				print("Buff applied: ", buff_type, " +", amount, " for ", duration, "s")
				# TODO: Buff System implementieren
		_:
			print("Unknown effect action: ", action)


# === SAVE / LOAD ===

func get_save_data() -> Dictionary:
	return {
		"inventory": _inventory.duplicate(),
		"hotbar": _hotbar.duplicate()
	}

func _show_pickup_dialogue(item_data: ItemData, custom_text: String = "") -> void:
	var player: Node3D = _get_player()
	if player == null:
		print("No player found for pickup dialogue")
		return
	
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		print("No DialogueManager found")
		return
	
	item_pickup_started.emit(item_data.item_id)
	
	# Hold Frame vom Player holen
	var hold_frame: int = 87
	if player.has_method("get_item_hold_frame"):
		hold_frame = player.get_item_hold_frame()
	
	# Text bestimmen
	var display_text: String = custom_text
	if display_text == "":
		if item_data.has_method("get_pickup_display_text"):
			display_text = item_data.get_pickup_display_text()
		else:
			var color_hex: String = item_data.get_rarity_color().to_html(false)
			display_text = "You got [color=#%s]%s[/color]!" % [color_hex, item_data.item_name]
	
	# Pickup Dialog starten
	if dialogue_manager.has_method("start_item_pickup"):
		dialogue_manager.start_item_pickup(player, item_data, display_text, hold_frame)
		
		# Auf Ende warten
		if not dialogue_manager.item_pickup_finished.is_connected(_on_pickup_finished):
			dialogue_manager.item_pickup_finished.connect(_on_pickup_finished.bind(item_data.item_id), CONNECT_ONE_SHOT)


func _on_pickup_finished(item_id: String) -> void:
	item_pickup_finished.emit(item_id)
		
func _get_player() -> Node3D:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		return tree.get_first_node_in_group("player") as Node3D
	return null

func load_save_data(data: Dictionary) -> void:
	_inventory.clear()
	_hotbar = ["", "", "", ""]
	
	if data.has("inventory"):
		var inv_data: Dictionary = data["inventory"]
		for item_id in inv_data:
			_inventory[item_id] = inv_data[item_id]
	
	if data.has("hotbar"):
		var hotbar_data: Array = data["hotbar"]
		for i in range(min(hotbar_data.size(), _hotbar.size())):
			_hotbar[i] = hotbar_data[i]
	
	inventory_changed.emit()
	
	for i in range(_hotbar.size()):
		hotbar_changed.emit(i, _hotbar[i])
	
	print("Inventory loaded - Items: ", _inventory.size())
