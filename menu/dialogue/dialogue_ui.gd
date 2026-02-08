extends CanvasLayer
class_name DialogueUI

signal dialogue_finished
signal choice_selected(choice_index: int)

@onready var panel: PanelContainer = $PanelContainer
@onready var dialogue_text: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/DialogueText
@onready var choices_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ChoicesContainer
@onready var continue_hint: Label = $PanelContainer/MarginContainer/VBoxContainer/ContinueHint

#const CHOICE_BUTTON_SCENE: PackedScene = preload("res://UI/Dialogue/choice_button.tscn")

var _is_typing: bool = false
var _full_text: String = ""
var _current_char_index: int = 0
var _type_speed: float = 0.03
var _type_timer: float = 0.0
var _has_choices: bool = false


func _ready() -> void:
	layer = 50
	visible = false
	continue_hint.text = "[Space] continue"


func _process(delta: float) -> void:
	if not visible:
		return
	
	if _is_typing:
		_type_timer -= delta
		if _type_timer <= 0.0:
			_type_timer = _type_speed
			_current_char_index += 1
			dialogue_text.visible_characters = _current_char_index
			
			if _current_char_index >= _full_text.length():
				_is_typing = false
				_on_typing_finished()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _is_typing:
			# Skip typing
			_is_typing = false
			dialogue_text.visible_characters = -1
			_on_typing_finished()
		elif not _has_choices:
			# Continue
			dialogue_finished.emit()
		
		get_viewport().set_input_as_handled()


func show_dialogue_line(line: DialogueLine) -> void:
	visible = true
	
	
	# Text mit Typewriter
	_full_text = line.text
	dialogue_text.text = _full_text
	dialogue_text.visible_characters = 0
	_current_char_index = 0
	_is_typing = true
	_type_timer = _type_speed
	
	# Choices
	_clear_choices()
	_has_choices = line.choices.size() > 0
	
	continue_hint.visible = false


func _on_typing_finished() -> void:
	if _has_choices:
		continue_hint.visible = false
	else:
		continue_hint.visible = true


func show_choices(choices: Array[DialogueChoice]) -> void:
	_clear_choices()
	_has_choices = choices.size() > 0
	
	if not _has_choices:
		return
	
	continue_hint.visible = false
	
	for i in range(choices.size()):
		var choice: DialogueChoice = choices[i]
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, choice.text]
		button.pressed.connect(func(): _on_choice_pressed(i))
		choices_container.add_child(button)


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()
	_has_choices = false


func _on_choice_pressed(index: int) -> void:
	_clear_choices()
	choice_selected.emit(index)


func hide_dialogue() -> void:
	visible = false
	_clear_choices()
