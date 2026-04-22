extends Node

signal dialogue_started(npc: NPC)
signal dialogue_ended(npc: NPC)
signal quest_added(quest_id: String)

@export_group("Typewriter")
@export var type_speed: float = 0.03
@export var skip_cooldown: float = 0.3
@export var end_cooldown: float = 0.5  # Cooldown nach Dialog-Ende

var _canvas: CanvasLayer = null
var _panel: Control = null
var _speaker_label: Label = null
var _text_label: RichTextLabel = null
var _choices_container: VBoxContainer = null
var _hint_label: Label = null

var _current_npc: NPC = null
var _current_dialogue: DialogueData = null
var _current_line_index: int = 0
var _is_active: bool = false

# Typewriter State
var _full_text: String = ""
var _current_char_index: int = 0
var _is_typing: bool = false
var _type_timer: float = 0.0
var _can_advance: bool = false
var _advance_cooldown: float = 0.0

var _choice_buttons: Array[Button] = []
var _choice_activation_timer: float = 0.0
const CHOICE_ACTIVATION_DELAY: float = 0.3
var _has_active_choices : bool = false

# End Cooldown - verhindert sofortiges Neu-Starten
var _end_cooldown_timer: float = 0.0

var _font: FontFile
var font_color: Color = Color(255, 234, 213)

var _is_item_pickup_mode: bool = false
var _pickup_player: Node3D = null
var _pickup_player_sprite: LayeredPixelSprite3D  = null
var _pickup_original_frame: int = 0
var _pickup_original_flip: bool = false
var _pickup_effect: Node3D = null
#var _pickup_hold_frame: int = 87  # Standard, wird überschrieben

signal item_pickup_finished

var _pending_item_pickups: Array[Dictionary] = []


func load_font() -> void:
	var font_path: String = "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path)


func _ready() -> void:
	load_font()
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_create_dialogue_ui")


func _create_dialogue_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 50
	add_child(_canvas)

	_panel = Control.new()        # NICHT PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -200
	_panel.offset_left = 0      # <- war 50, jetzt schmaler
	_panel.offset_right = 0    # <- war -50, jetzt schmaler
	_panel.offset_bottom = 0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_panel)

	# --- NEU: Panel-Style leeren, damit nichts den Shader überzeichnet ---
	var empty_style := StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", empty_style)

	# --- NEU: ColorRect mit Shader als Background ---
	# Muss VOR dem MarginContainer child werden, damit es hinter dem Text liegt.
	# Wichtig: show_behind_parent, damit der PanelContainer es nicht ins Layout zwingt / überdeckt.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true

	var shader: Shader = load("res://menu/shaders/dialogue_bg.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Optional: Uniforms hier setzen, falls du nicht die Shader-Defaults willst
	# mat.set_shader_parameter("bg_color", Color(0.05, 0.05, 0.1, 0.92))
	# mat.set_shader_parameter("fade_left", 0.12)
	bg.material = mat
	_panel.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 30)
	_panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_label.add_theme_font_override("normal_font", _font)
	_text_label.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(_text_label)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_override("font", _font)
	_speaker_label.add_theme_font_size_override("font_size", 22)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_label.anchor_left = 0.0
	_speaker_label.anchor_top = 0.0
	_speaker_label.anchor_right = 0.0
	_speaker_label.anchor_bottom = 0.0
	_speaker_label.offset_left = 60
	_speaker_label.offset_top = 20
	_speaker_label.offset_right = 400
	_speaker_label.offset_bottom = 18
	_panel.add_child(_speaker_label)
	
	_choices_container = VBoxContainer.new()
	_choices_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choices_container.add_theme_constant_override("separation", 8)
	_choices_container.alignment = BoxContainer.ALIGNMENT_END
	# Oberhalb des Panels, rechtsbündig
	_choices_container.anchor_left = 1.0
	_choices_container.anchor_top = 0.0
	_choices_container.anchor_right = 1.0
	_choices_container.anchor_bottom = 0.0
	_choices_container.offset_left = -400   # Breite des Choice-Bereichs
	_choices_container.offset_top = -250    # wie weit über der Box
	_choices_container.offset_right = -20
	_choices_container.offset_bottom = 0  # knapp über der Dialogbox-Oberkante
	_choices_container.grow_vertical = Control.GROW_DIRECTION_BEGIN  # wächst nach oben
	_panel.add_child(_choices_container)
	
	_hint_label = Label.new()
	_hint_label.text = "[Continue]"
	_hint_label.add_theme_font_override("font", _font)
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.modulate = Color(0.7, 0.7, 0.7)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.anchor_left = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -200
	_hint_label.offset_top = -50
	_hint_label.offset_right = -60
	_hint_label.offset_bottom = -30
	_panel.add_child(_hint_label)
	
	_panel.visible = false
	print("DialogueManager UI created!")


func _process(delta: float) -> void:
	# End Cooldown Timer
	if _end_cooldown_timer > 0.0:
		_end_cooldown_timer -= delta
		
	if _choice_activation_timer > 0.0:
		_choice_activation_timer -= delta
		if _choice_activation_timer <= 0.0:
			_activate_choices()
	
	if not _is_active:
		return
	
	# Typewriter
	if _is_typing:
		_type_timer -= delta
		if _type_timer <= 0.0:
			_type_timer = type_speed
			_current_char_index += 1
			_text_label.visible_characters = _current_char_index
			
			if _current_char_index >= _full_text.length():
				_finish_typing()
	
	# Advance Cooldown
	if _advance_cooldown > 0.0:
		_advance_cooldown -= delta
		if _advance_cooldown <= 0.0:
			_can_advance = true
			_update_hint_label()


func _input(event: InputEvent) -> void:
	if not _is_active:
		return
	
	if event.is_action_pressed("hotbar_w", false) or event.is_action_pressed("ui_accept", false) or event.is_action_pressed("ui_cancel", false):
		_handle_input()
		get_viewport().set_input_as_handled()


func _handle_input() -> void:
	if _is_typing:
		_skip_typing()
		return
	
	if not _can_advance:
		return
		
	if _is_item_pickup_mode:
		_end_item_pickup()
		return
	
	if _current_dialogue == null:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	if line and line.choices.size() > 0:
		# Bei Choices: Fokussierten Button aktivieren
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is Button and focused.get_parent() == _choices_container:
			focused.emit_signal("pressed")
		return
	
	_advance_dialogue()
	
func _show_item_pickup_line(text: String) -> void:
	"""Zeigt den Pickup-Text mit Typewriter-Effekt"""
	_speaker_label.text = ""  # Kein Speaker bei Item Pickup
	
	_full_text = text
	_text_label.text = _full_text
	_text_label.visible_characters = 0
	_current_char_index = 0
	
	# Typewriter aktivieren (genau wie bei NPC Dialog!)
	_is_typing = true
	_type_timer = type_speed
	_can_advance = false
	_advance_cooldown = 0.0
	
	_hint_label.visible = false
	
	# Choices leeren
	for child in _choices_container.get_children():
		child.queue_free()
	
	_panel.visible = true


func _spawn_pickup_effect(player: Node3D, item_data: ItemData) -> void:
	"""Spawnt den 3D Effekt über dem Spieler"""
	_pickup_effect = Node3D.new()
	_pickup_effect.name = "PickupEffect"
	_pickup_effect.process_mode = Node.PROCESS_MODE_ALWAYS
	
	player.get_tree().current_scene.add_child(_pickup_effect)
	_pickup_effect.global_position = player.global_position + Vector3(-0.1, 0.4, 0)
	
	# Shine Effekt ZUERST (hinter dem Item)
	var shine_pivot := _create_shine_effect()
	_pickup_effect.add_child(shine_pivot)
	
	# Item Sprite DARÜBER
	var item_sprite := Sprite3D.new()
	item_sprite.name = "ItemSprite"
	item_sprite.texture = item_data.icon
	item_sprite.pixel_size = 0.015
	item_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	item_sprite.transparent = true
	item_sprite.render_priority = 6
	_pickup_effect.add_child(item_sprite)
	
	# Animation: Item steigt EINMAL hoch und bleibt
	var rise_tween := item_sprite.create_tween()
	rise_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rise_tween.tween_property(item_sprite, "position:y", 0.2, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _create_shine_effect() -> Node3D:
	var shine_pivot := Node3D.new()
	shine_pivot.name = "ShinePivot"
	shine_pivot.position.x += -0.0
	shine_pivot.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var ray_count: int = 8
	
	for i in range(ray_count):
		var angle: float = (TAU / ray_count) * i
		
		var ray := MeshInstance3D.new()
		ray.process_mode = Node.PROCESS_MODE_ALWAYS
		
		# Custom Mesh: Spitze innen, breit außen, mit Gradient
		ray.mesh = _create_gradient_ray_mesh()
		
		# Material - Additiv, Unshaded
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.95, 0.8, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		
		mat.render_priority = 0          # Shine "unten"
		mat.sorting_offset = -0.01  
		
		ray.material_override = mat
		
		# Rotation: Strahl zeigt in seine Richtung nach außen
		ray.rotation.z = angle+120
		
		
		shine_pivot.add_child(ray)
	
	# Rotation der gesamten Strahlen-Gruppe
	var rotate_tween := shine_pivot.create_tween()
	rotate_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rotate_tween.set_loops()
	rotate_tween.tween_property(shine_pivot, "rotation:z", TAU, 20.0).set_trans(Tween.TRANS_LINEAR)
	
	
	# Leichtes Pulsieren
	var pulse_tween := shine_pivot.create_tween()
	pulse_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	pulse_tween.set_loops()
	pulse_tween.tween_property(shine_pivot, "scale", Vector3(1.08, 1.08, 1.08), 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(shine_pivot, "scale", Vector3(0.95, 0.95, 0.95), 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	var rise_tween := shine_pivot.create_tween()
	rise_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rise_tween.tween_property(shine_pivot, "position:y", 0.2, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	return shine_pivot

func _create_gradient_ray_mesh() -> ArrayMesh:
	"""
	Erstellt einen Lichtstrahl:
	- Spitze bei Y=0 (Zentrum)
	- Breit bei Y=length (außen)
	- Alpha-Gradient: Innen hell (0.4) → Außen transparent (0.0)
	"""
	var mesh := ArrayMesh.new()
	
	var length: float = 2.0
	var width_tip: float = 0.02   # Spitze (innen) - sehr schmal
	var width_base: float = 0.3  # Basis (außen) - breiter
	
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	# Dreieck: Spitze unten (bei 0), breit oben (bei length)
	# Die Spitze ist im Zentrum, die breite Seite zeigt nach außen
	
	# Vertex 0: Spitze (Zentrum) - am hellsten
	vertices.push_back(Vector3(0, 0.05, 0))
	colors.push_back(Color(1.0, 0.98, 0.9, 0.1))
	
	# Vertex 1: Außen links - transparent
	vertices.push_back(Vector3(-width_base * 0.5, length, 0))
	colors.push_back(Color(1.0, 0.98, 0.9, 0.0))
	
	# Vertex 2: Außen rechts - transparent
	vertices.push_back(Vector3(width_base * 0.5, length, 0))
	colors.push_back(Color(1.0, 0.98, 0.9, 0.0))
	
	# Ein Dreieck
	indices.push_back(0)
	indices.push_back(1)
	indices.push_back(2)
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh

func _end_item_pickup() -> void:
	_panel.visible = false
	_is_active = false
	_is_typing = false
	_can_advance = false
	_is_item_pickup_mode = false
	
	_end_cooldown_timer = end_cooldown
	
	get_tree().paused = false
	
	# 3D Effekt entfernen
	if _pickup_effect and is_instance_valid(_pickup_effect):
		_pickup_effect.queue_free()
		_pickup_effect = null
	
	# Player wiederherstellen
	if _pickup_player:
		if _pickup_player.has_method("set_frozen"):
			_pickup_player.set_frozen(false)
		
		if _pickup_player_sprite:
			_pickup_player_sprite.frame = _pickup_original_frame
			_pickup_player_sprite.flip_h = _pickup_original_flip
			
			if _pickup_player_sprite.has_layer("weapon"):
				_pickup_player_sprite.set_layer_visible("weapon", true)
			if _pickup_player_sprite.has_layer("vector_anchor"):
				_pickup_player_sprite.set_layer_visible("vector_anchor", true)
	
	_pickup_player = null
	_pickup_player_sprite = null
	
	item_pickup_finished.emit()
	
	# NEU: Pending Item Pickups verarbeiten
	_process_pending_pickups()


func _process_pending_pickups() -> void:
	if _pending_item_pickups.is_empty():
		return
	
	# Kurz warten, damit cooldown nicht blockt
	await get_tree().create_timer(0.1).timeout
	
	if _pending_item_pickups.is_empty():
		return
	
	var pickup: Dictionary = _pending_item_pickups.pop_front()
	var player: Node3D = pickup.get("player")
	var item_data: ItemData = pickup.get("item_data")
	var custom_text: String = pickup.get("custom_text", "")
	var hold_frame: int = pickup.get("hold_frame", 90)
	
	if player and is_instance_valid(player) and item_data:
		_end_cooldown_timer = 0.0  # Cooldown zurücksetzen für Queue
		_start_item_pickup_internal(player, item_data, custom_text, hold_frame)

func _skip_typing() -> void:
	_is_typing = false
	_text_label.visible_characters = -1
	_current_char_index = _full_text.length()
	
	_can_advance = false
	_advance_cooldown = skip_cooldown
	_hint_label.visible = false
	
	# Choices anzeigen falls vorhanden
	_show_choices_if_any()


func _finish_typing() -> void:
	_is_typing = false
	
	_can_advance = false
	_advance_cooldown = skip_cooldown
	
	_show_choices_if_any()


func _show_choices_if_any() -> void:
	if _current_dialogue == null:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	if line == null or line.choices.size() == 0:
		_has_active_choices = false
		return
	
	_choice_buttons.clear()
	
	for i in range(line.choices.size()):
		var choice: DialogueChoice = line.choices[i]
		if choice == null:
			continue
		
		if choice.condition != "":
			var quest_manager: Node = get_node_or_null("/root/QuestManager")
			if quest_manager and not quest_manager.check_condition(choice.condition):
				continue
		
		var button := Button.new()
		button.text = "%s" % [choice.text]
		button.add_theme_font_override("font", _font)
		button.pressed.connect(_on_choice_selected.bind(i))
		button.disabled = true  # Erstmal deaktiviert
		
		_choices_container.add_child(button)
		_choice_buttons.append(button)
	
	# Focus Neighbors setzen
	for j in range(_choice_buttons.size()):
		var btn: Button = _choice_buttons[j]
		if j > 0:
			btn.focus_neighbor_top = _choice_buttons[j - 1].get_path()
		if j < _choice_buttons.size() - 1:
			btn.focus_neighbor_bottom = _choice_buttons[j + 1].get_path()
	
	if _choice_buttons.size() > 1:
		_choice_buttons[0].focus_neighbor_top = _choice_buttons[_choice_buttons.size() - 1].get_path()
		_choice_buttons[_choice_buttons.size() - 1].focus_neighbor_bottom = _choice_buttons[0].get_path()
	
	_has_active_choices = _choice_buttons.size() > 0
	
	# Timer starten für Aktivierung
	if _has_active_choices:
		_choice_activation_timer = CHOICE_ACTIVATION_DELAY


func _activate_choices() -> void:
	for btn in _choice_buttons:
		if is_instance_valid(btn):
			btn.disabled = false
	
	if _choice_buttons.size() > 0 and is_instance_valid(_choice_buttons[0]):
		_choice_buttons[0].grab_focus()

func _update_hint_label() -> void:
	if _current_dialogue == null:
		_hint_label.visible = false
		return
	
	if _current_line_index >= _current_dialogue.dialogue_lines.size():
		_hint_label.visible = false
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	if line and line.choices.size() > 0:
		_hint_label.visible = false
	else:
		_hint_label.visible = _can_advance


func is_dialogue_active() -> bool:
	return _is_active


func is_on_cooldown() -> bool:
	return _end_cooldown_timer > 0.0


func start_dialogue(npc: NPC, dialogue_data: Resource) -> void:
	if _end_cooldown_timer > 0.0:
		print("Dialogue on cooldown, ignoring")
		return
	
	if _panel == null:
		push_error("Dialogue UI not created!")
		return
	
	if dialogue_data == null or not dialogue_data is DialogueData:
		push_warning("Invalid dialogue data!")
		if npc:
			npc.end_dialogue()
		return
	
	_current_npc = npc
	_current_dialogue = dialogue_data as DialogueData
	_current_line_index = _find_starting_line()
	_is_active = true
	_has_active_choices = false
	
	print("Starting dialogue at line: ", _current_line_index)
	
	get_tree().paused = true
	
	dialogue_started.emit(npc)
	
	_show_current_line()

func _find_starting_line() -> int:
	"""Findet den ersten Block dessen Start-Condition erfüllt ist"""
	if _current_dialogue == null:
		return 0
	
	var found_blocks: Dictionary = {}  # block_id -> first_line_index
	
	# Alle Blöcke und ihre Start-Indizes sammeln
	for i in range(_current_dialogue.dialogue_lines.size()):
		var line: DialogueLine = _current_dialogue.dialogue_lines[i]
		if line == null:
			continue
		
		var block: String = line.block_id if line.block_id != "" else "default_%d" % i
		
		# Ersten Index für jeden Block merken
		if not found_blocks.has(block):
			found_blocks[block] = {
				"index": i,
				"condition": line.condition
			}
	
	print("Found blocks: ", found_blocks)
	
	# Ersten Block finden dessen Condition erfüllt ist
	for i in range(_current_dialogue.dialogue_lines.size()):
		var line: DialogueLine = _current_dialogue.dialogue_lines[i]
		if line == null:
			continue
		
		var block: String = line.block_id if line.block_id != "" else "default_%d" % i
		var block_data: Dictionary = found_blocks.get(block, {})
		
		# Ist dies die erste Line dieses Blocks?
		if block_data.get("index", -1) == i:
			var condition: String = block_data.get("condition", "")
			
			# Condition prüfen
			if condition == "" or QuestManager.check_condition(condition):
				print("Starting with block '", block, "' at line ", i)
				return i
	
	return 0

func _show_current_line() -> void:
	if _current_dialogue == null:
		_end_dialogue()
		return
	
	if _current_line_index >= _current_dialogue.dialogue_lines.size():
		_end_dialogue()
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	if line == null:
		push_error("DialogueLine at index ", _current_line_index, " is null!")
		_end_dialogue()
		return
	
	# NEU: Line-spezifische Condition prüfen (für Lines INNERHALB eines Blocks)
	# Aber NUR wenn es eine Condition hat UND nicht die Block-Start-Line ist
	if line.condition != "":
		var is_block_start: bool = _is_block_start_line(_current_line_index)
		
		if not is_block_start and not QuestManager.check_condition(line.condition):
			# Diese Line überspringen, zur nächsten
			print("Skipping line ", _current_line_index, " (condition not met)")
			_current_line_index += 1
			_show_current_line()
			return
	
	var speaker: String = line.speaker_name
	if speaker == "" and _current_npc:
		speaker = _current_npc.npc_name
	_speaker_label.text = speaker
	
	_full_text = line.text
	_text_label.text = _full_text
	_text_label.visible_characters = 0
	_current_char_index = 0
	_is_typing = true
	_type_timer = type_speed
	_can_advance = false
	_advance_cooldown = 0.0
	
	_hint_label.visible = false
	
	for child in _choices_container.get_children():
		child.queue_free()
	
	_panel.visible = true

func _is_block_start_line(index: int) -> bool:
	"""Prüft ob diese Line die erste ihres Blocks ist"""
	if _current_dialogue == null:
		return false
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[index]
	if line == null:
		return false
	
	var block_id: String = line.block_id
	if block_id == "":
		return true  # Lines ohne Block sind immer "Start"
	
	# Prüfen ob es eine frühere Line mit dem gleichen block_id gibt
	for i in range(index):
		var earlier_line: DialogueLine = _current_dialogue.dialogue_lines[i]
		if earlier_line and earlier_line.block_id == block_id:
			return false  # Es gibt eine frühere Line im gleichen Block
	
	return true

func _advance_dialogue() -> void:
	if _current_dialogue == null:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	if line == null:
		_end_dialogue()
		return
	
	# Action ausführen
	if line.action != "":
		_execute_action(line.action)
	
	# Dialog beenden?
	if line.ends_dialogue:
		_end_dialogue()
		return
	
	# Nächste Line bestimmen
	if line.next_line_index >= 0:
		# Expliziter Sprung
		_current_line_index = line.next_line_index
	else:
		# Nächste Line im Block
		_current_line_index += 1
		
		# Prüfen ob wir den Block verlassen haben
		if _current_line_index < _current_dialogue.dialogue_lines.size():
			var next_line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
			var current_block: String = line.block_id
			var next_block: String = next_line.block_id if next_line else ""
			
			# Wenn der Block wechselt UND der nächste Block eine Condition hat,
			# dann Dialog beenden (nicht automatisch in anderen Block springen)
			if current_block != "" and next_block != "" and current_block != next_block:
				print("Block change detected, ending dialogue")
				_end_dialogue()
				return
	
	_show_current_line()


func _on_choice_selected(choice_index: int) -> void:
	if _current_dialogue == null:
		return
	
	if _is_typing or not _can_advance:
		return
	
	var line: DialogueLine = _current_dialogue.dialogue_lines[_current_line_index]
	
	if line == null or choice_index >= line.choices.size():
		return
	
	var choice: DialogueChoice = line.choices[choice_index]
	
	if choice == null:
		return
	
	if choice.action != "":
		_execute_action(choice.action)
	
	if choice.next_line_index >= 0:
		_current_line_index = choice.next_line_index
	else:
		_current_line_index = _current_dialogue.dialogue_lines.size()
	
	_show_current_line()


func _end_dialogue() -> void:
	if _is_item_pickup_mode:
		_end_item_pickup()
		return
	
	_panel.visible = false
	_is_active = false
	_is_typing = false
	_can_advance = false
	
	_end_cooldown_timer = end_cooldown
	
	get_tree().paused = false
	
	if _current_npc:
		_current_npc.end_dialogue()
		dialogue_ended.emit(_current_npc)
	
	_current_npc = null
	_current_dialogue = null
	_current_line_index = 0
	
	# NEU: Pending Item Pickups verarbeiten
	_process_pending_pickups()
	
	

func start_item_pickup(player: Node3D, item_data: ItemData, custom_text: String = "", hold_frame: int = 90) -> void:
	# Wenn gerade ein Dialog aktiv ist -> in Queue packen
	if _is_active or _end_cooldown_timer > 0.0:
		print("Queueing item pickup for later: ", item_data.item_name)
		_pending_item_pickups.append({
			"player": player,
			"item_data": item_data,
			"custom_text": custom_text,
			"hold_frame": hold_frame
		})
		return
	
	_start_item_pickup_internal(player, item_data, custom_text, hold_frame)

func _start_item_pickup_internal(player: Node3D, item_data: ItemData, custom_text: String = "", hold_frame: int = 90) -> void:
	if _panel == null:
		push_error("Dialogue UI not created!")
		return
	
	print("Starting item pickup for: ", item_data.item_name)
	
	_is_item_pickup_mode = true
	_pickup_player = player
	
	# Player Sprite auf Hold-Frame setzen
	_pickup_player_sprite = player.get_node_or_null("charactersprite") as LayeredPixelSprite3D
	if _pickup_player_sprite:
		_pickup_original_frame = _pickup_player_sprite.frame
		_pickup_original_flip = _pickup_player_sprite.flip_h
		_pickup_player_sprite.frame = hold_frame
		_pickup_player_sprite.flip_h = false
		
		if _pickup_player_sprite.has_layer("weapon"):
			_pickup_player_sprite.set_layer_visible("weapon", false)
		if _pickup_player_sprite.has_layer("vector_anchor"):
			_pickup_player_sprite.set_layer_visible("vector_anchor", false)
	
	# Player einfrieren
	if player.has_method("set_frozen"):
		player.set_frozen(true)
	
	# 3D Effekt spawnen
	_spawn_pickup_effect(player, item_data)
	
	# Standard Dialog-Variablen
	_current_npc = null
	_current_dialogue = null
	_current_line_index = 0
	_is_active = true
	_has_active_choices = false
	
	get_tree().paused = true
	
	# Text bestimmen
	var display_text: String = custom_text
	if display_text == "":
		if item_data.has_method("get_pickup_display_text"):
			display_text = item_data.get_pickup_display_text()
		else:
			var color_hex: String = item_data.get_rarity_color().to_html(false)
			display_text = "You got [color=#%s]%s[/color]!" % [color_hex, item_data.item_name]
	
	_show_item_pickup_line(display_text)


func _execute_action(action: String) -> void:
	action = action.strip_edges()
	action = action.replace('"', '')
	action = action.replace("'", '')
	
	if action == "":
		return
	
	
	# Dann Komma prüfen
	if "," in action:
		var actions: PackedStringArray = action.split(",")
		for act in actions:
			var clean_act: String = act.strip_edges()
			if clean_act != "":
				_execute_single_action(clean_act)
		return
	
	_execute_single_action(action)


func _execute_single_action(action: String) -> void:
	# Nochmal säubern (falls von split() kommend)
	action = action.strip_edges()
	action = action.replace('"', '')
	action = action.replace("'", '')
	
	if action == "":
		return

	# Auf Negation prüfen
	var negated: bool = action.begins_with("!")
	if negated:
		action = action.substr(1)

	var parts: PackedStringArray = action.split(":")

	if parts.size() < 2:
		push_warning("Invalid action format: " + action)
		return

	var type: String = parts[0].strip_edges()
	var value: String = parts[1].strip_edges()
	
	print("Executing action: ", type, " -> ", value)

	match type:
		"add_quest":
			QuestManager.add_quest(value)
		
		"complete_quest":
			QuestManager.update_quest_progress(value, 999)
		
		"turn_in_quest":
			QuestManager.turn_in_quest(value)
		
		"give_gold":
			var amount: int = int(value)
			GameManager.player_data.gold += amount
			GameManager.player_data.gold_changed.emit(GameManager.player_data.gold)
			
		"give_item":
			var amount: int = 1
			var custom_text: String = ""
			if parts.size() >= 3:
				amount = int(parts[2])
			if parts.size() >= 4:
				custom_text = parts[3]
				
			InventoryManager.add_item(value, amount, true, custom_text)
			
		"give_item_silent":
			var amount: int = 1
			if parts.size() >= 3:
				amount = int(parts[2])
			InventoryManager.add_item(value, amount, false)
		
		"give_exp":
			var amount: int = int(value)
			GameManager.player_data.add_exp(amount)
		
		"remove_item":
			var amount: int = 1
			if parts.size() >= 3:
				amount = int(parts[2])
			InventoryManager.remove_item(value, amount)
		
		"set_flag":
			if GameManager.has_method("set_flag"):
				GameManager.set_flag(value, true)
		
		"clear_flag":
			if GameManager.has_method("clear_flag"):
				GameManager.clear_flag(value)
		
		_:
			push_warning("Unknown action type: " + type)
