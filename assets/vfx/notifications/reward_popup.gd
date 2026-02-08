extends Node3D
class_name RewardPopup

@export var float_speed: float = 0.8
@export var float_distance: float = 0.6
@export var fade_delay: float = 0.5
@export var fade_duration: float = 0.4
@export var exp_color: Color = Color(0.4, 0.8, 1.0)  # Hellblau
@export var gold_color: Color = Color(1.0, 0.85, 0.2)  # Gold

@onready var label: Label3D = $Label3D

var _start_y: float = 0.0
var _elapsed: float = 0.0
var _total_duration: float = 0.0


func _ready() -> void:
	_start_y = position.y
	_total_duration = fade_delay + fade_duration
	
	# Label Styling
	if label:
		label.outline_modulate = Color(0, 0, 0, 0.8)


func setup_exp(amount: int) -> void:
	if label:
		label.text = "+ %d EXP" % amount
		label.modulate = exp_color


func setup_gold(amount: int) -> void:
	if label:
		label.text = "+ %d Gold" % amount
		label.modulate = gold_color


func setup_combined(exp_amount: int, gold_amount: int) -> void:
	if label:
		label.text = "+ %d EXP  + %d Gold" % [exp_amount, gold_amount]
		label.modulate = exp_color  # Oder eine neutrale Farbe


func _process(delta: float) -> void:
	_elapsed += delta
	
	# Nach oben schweben
	var progress: float = _elapsed / _total_duration
	position.y = _start_y + float_distance * min(progress * 2.0, 1.0)
	
	# Ausblenden nach delay
	if _elapsed > fade_delay and label:
		var fade_progress: float = (_elapsed - fade_delay) / fade_duration
		label.modulate.a = 1.0 - fade_progress
	
	# Aufräumen
	if _elapsed >= _total_duration:
		queue_free()
