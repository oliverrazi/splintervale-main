extends Node

signal dialogue_started(npc: NPC)
signal dialogue_ended(npc: NPC)
signal quest_added(quest_id: String)

var _dialogue_ui: DialogueUI = null
var _current_npc: NPC = null
var _current_dialogue: DialogueData = null
var _current_line_index: int = 0

const DIALOGUE_UI_SCENE: PackedScene = preload("res://menu/dialogue/dialogue_ui.tscn")


func _ready() -> void:
	# UI erstellen
	_dialogue_ui = DIALOGUE_UI_SCENE.instantiate() as DialogueUI
	add_child(_dialogue_ui)
	
	_dialogue_ui.dialogue_finished.connect(_on_dialogue_finished)
	_dialogue_ui.choice_selected.connect(_on_choice_selected)


func start_dialogue(npc: NPC, dialogue_data: Resource) -> void:
	if dialogue_data == null or not dialogue_data is DialogueData:
		push_warning("Invalid dialogue data for NPC: ", npc.npc_name)
		npc.end_dialogue()
		return
	
	_current_npc = npc
	_current_dialogue = dialogue_data as DialogueData
	_current_line_index = 0
	
	# Spiel pausieren (optional)
	get_tree().paused = true
	_dialogue_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	
	dialogue_started.emit(npc)
	
	_show_current_line()


func _show_current_line() -> void:
	if _current_dialogue == null:
		return
	
	if _current_line_index >= _current_dialogue.dialogue_lines.size():
		_end_dialogue()
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	# Bedingung prüfen
	if line.condition != "" and not _check_condition(line.condition):
		_current_line_index += 1
		_show_current_line()
		return
	
	# Speaker Name - falls leer, NPC Name nehmen
	if line.speaker_name == "" and _current_npc:
		line.speaker_name = _current_npc.npc_name
	
	_dialogue_ui.show_dialogue_line(line)
	
	# Choices anzeigen nach Typing
	if line.choices.size() > 0:
		await get_tree().create_timer(0.1).timeout
		_show_choices_when_ready(line)


func _show_choices_when_ready(line: DialogueLine) -> void:
	# Warten bis Typing fertig
	while _dialogue_ui._is_typing:
		await get_tree().process_frame
	
	# Gefilterte Choices
	var valid_choices: Array[DialogueChoice] = []
	for choice in line.choices:
		if choice.condition == "" or _check_condition(choice.condition):
			valid_choices.append(choice)
	
	if valid_choices.size() > 0:
		_dialogue_ui.show_choices(valid_choices)


func _on_dialogue_finished() -> void:
	if _current_dialogue == null:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	# Aktion ausführen
	if line.action != "":
		_execute_action(line.action)
	
	# Nächste Zeile
	_current_line_index += 1
	_show_current_line()


func _on_choice_selected(choice_index: int) -> void:
	if _current_dialogue == null:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	# Gefilterte Choices holen (gleiche Logik wie beim Anzeigen)
	var valid_choices: Array[DialogueChoice] = []
	for choice in line.choices:
		if choice.condition == "" or _check_condition(choice.condition):
			valid_choices.append(choice)
	
	if choice_index >= valid_choices.size():
		return
	
	var choice: DialogueChoice = valid_choices[choice_index]
	
	# Aktion ausführen
	if choice.action != "":
		_execute_action(choice.action)
	
	# Zur nächsten Zeile springen
	if choice.next_line_index >= 0:
		_current_line_index = choice.next_line_index
	else:
		_current_line_index = _current_dialogue.dialogue_lines.size()  # Ende
	
	_show_current_line()


func _end_dialogue() -> void:
	_dialogue_ui.hide_dialogue()
	
	get_tree().paused = false
	
	if _current_npc:
		_current_npc.end_dialogue()
		dialogue_ended.emit(_current_npc)
	
	_current_npc = null
	_current_dialogue = null
	_current_line_index = 0


func _check_condition(condition: String) -> bool:
	"""
	Prüft Bedingungen wie:
	- "has_quest:quest_001"
	- "quest_complete:quest_001"
	- "has_item:key_001"
	- "flag:talked_to_elder"
	"""
	var parts: PackedStringArray = condition.split(":")
	if parts.size() < 2:
		return true
	
	var type: String = parts[0]
	var value: String = parts[1]
	
	match type:
		"has_quest":
			# return QuestManager.has_quest(value)
			return false  # TODO: QuestManager implementieren
		"quest_complete":
			# return QuestManager.is_quest_complete(value)
			return false
		"has_item":
			# return InventoryManager.has_item(value)
			return false
		"flag":
			# return GameManager.get_flag(value)
			return false
		_:
			return true


func _execute_action(action: String) -> void:
	"""
	Führt Aktionen aus wie:
	- "add_quest:quest_001"
	- "complete_quest:quest_001"
	- "give_item:potion:3"
	- "set_flag:talked_to_elder"
	- "give_gold:100"
	"""
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return
	
	var type: String = parts[0]
	var value: String = parts[1]
	
	match type:
		"add_quest":
			print("Quest added: ", value)
			quest_added.emit(value)
			# QuestManager.add_quest(value)
		"complete_quest":
			print("Quest completed: ", value)
			# QuestManager.complete_quest(value)
		"give_item":
			var amount: int = int(parts[2]) if parts.size() > 2 else 1
			print("Item given: ", value, " x", amount)
			# InventoryManager.add_item(value, amount)
		"set_flag":
			print("Flag set: ", value)
			# GameManager.set_flag(value, true)
		"give_gold":
			var amount: int = int(value)
			print("Gold given: ", amount)
			GameManager.player_data.gold += amount
			GameManager.player_data.gold_changed.emit(GameManager.player_data.gold)
		"give_exp":
			var amount: int = int(value)
			print("EXP given: ", amount)
			GameManager.player_data.add_exp(amount)
