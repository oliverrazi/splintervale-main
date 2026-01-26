extends Node3D
class_name EnemyHPBar

@export var hide_when_full: bool = true
@export var fade_delay: float = 2.5
@export var trail_delay: float = 0.5  # Verzögerung bevor gelber Balken schrumpft
@export var trail_speed: float = 0.5  # Sekunden für Trail-Animation

@onready var viewport: SubViewport = $SubViewport
@onready var background: ColorRect = $SubViewport/Control/Background
@onready var trail_fill: ColorRect  # Gelber Balken (wird erstellt)
@onready var fill: ColorRect = $SubViewport/Control/Fill
@onready var bar_sprite: Sprite3D = $BarSprite

var _max_width: float = 62.0
var _visible_timer: float = 0.0
var _is_fading: bool = false

var _trail_tween: Tween = null
var _current_ratio: float = 1.0


func _ready() -> void:
	bar_sprite.texture = viewport.get_texture()
	
	# Trail-Balken erstellen (gelb, hinter dem roten)
	_create_trail_fill()
	
	# Rote Farbe für HP
	fill.color = Color(0.412, 0.002, 0.837, 1.0)
	
	if hide_when_full:
		visible = false


func _create_trail_fill() -> void:
	trail_fill = ColorRect.new()
	trail_fill.color = Color(0.862, 0.678, 0.055, 1.0)  # Gelb/Orange
	trail_fill.position = Vector2(1, 1)
	trail_fill.size = Vector2(_max_width, 6)
	
	# Trail HINTER dem Fill einfügen
	var control: Control = $SubViewport/Control
	control.add_child(trail_fill)
	control.move_child(trail_fill, 1)  # Nach Background, vor Fill


func _process(delta: float) -> void:
	if not visible or _is_fading:
		return
	
	if _visible_timer > 0:
		_visible_timer -= delta
		if _visible_timer <= 0:
			_fade_out()


func set_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	
	var new_ratio := float(current) / float(maximum)
	var old_ratio := _current_ratio
	
	# Nur bei Schaden den Trail animieren
	if new_ratio < old_ratio:
		_animate_trail(old_ratio, new_ratio)
	
	_current_ratio = new_ratio
	
	# Roter Balken sofort aktualisieren
	fill.size.x = _max_width * new_ratio
	
	if hide_when_full and new_ratio >= 1.0:
		return
	
	_show()
	_visible_timer = fade_delay


func _animate_trail(from_ratio: float, to_ratio: float) -> void:
	# Alten Tween stoppen
	if _trail_tween and _trail_tween.is_valid():
		_trail_tween.kill()
	
	# Trail auf alten Wert setzen
	trail_fill.size.x = _max_width * from_ratio
	
	# Nach Verzögerung schrumpfen
	_trail_tween = create_tween()
	_trail_tween.tween_interval(trail_delay)
	_trail_tween.tween_property(trail_fill, "size:x", _max_width * to_ratio, trail_speed)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_QUAD)


func _show() -> void:
	if visible and not _is_fading:
		return
	
	_is_fading = false
	visible = true
	bar_sprite.modulate.a = 1.0


func _fade_out() -> void:
	if _is_fading:
		return
	
	_is_fading = true
	
	var tween := create_tween()
	tween.tween_property(bar_sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		visible = false
		_is_fading = false
	)
