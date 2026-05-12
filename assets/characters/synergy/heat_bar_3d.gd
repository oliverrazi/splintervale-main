extends Node3D
class_name HeatBar3D

## Heat-Bar unter dem Spieler. Erscheint nur wenn Heat > 0.
## Farbe wechselt blau → gelb → rot je nach Heat-Level.
## Pulsiert während Overheat-Phase.

@export var fade_in_time: float = 0.15
@export var fade_out_time: float = 0.4

@export var color_low: Color = Color(0.4, 0.7, 1.0, 1.0)        # Blau
@export var color_mid: Color = Color(1.0, 0.85, 0.2, 1.0)        # Gelb
@export var color_high: Color = Color(1.0, 0.3, 0.2, 1.0)        # Rot
@export var color_overheat: Color = Color(1.0, 0.1, 0.05, 1.0)   # Dunkles Rot

@export_group("Pulse")
@export var pulse_threshold: float = 0.7   ## Ab wann pulsiert die Bar
@export var pulse_speed_low: float = 4.0    ## Pulsfrequenz bei 70%
@export var pulse_speed_high: float = 9.0   ## Pulsfrequenz bei 100%

@export_group("Icon")
@export var icon_texture: Texture2D
@export var icon_offset_x: float = 2.25  ## Pixel rechts der Bar
@export var icon_pixel_size: float = 0.04 



@onready var viewport: SubViewport = $SubViewport
@onready var background: ColorRect = $SubViewport/Control/Background
@onready var fill: ColorRect = $SubViewport/Control/Fill
@onready var bar_sprite: Sprite3D = $BarSprite

var _max_width: float = 62.0
var _is_overheating: bool = false
var _overheat_pulse_time: float = 0.0

var _pulse_time: float = 0.0
var _current_normalized: float = 0.0

var _icon_sprite: Sprite3D = null


func _ready() -> void:
	bar_sprite.texture = viewport.get_texture()
	bar_sprite.no_depth_test = true
	if icon_texture != null:
		_create_icon_sprite()
	
	# Initial unsichtbar
	visible = false
	bar_sprite.modulate.a = 0.0

func _create_icon_sprite() -> void:
	_icon_sprite = Sprite3D.new()
	_icon_sprite.texture = icon_texture
	_icon_sprite.pixel_size = icon_pixel_size
	_icon_sprite.no_depth_test = true
	_icon_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_icon_sprite.position = Vector3(icon_offset_x, 0.0, 0.0)
	_icon_sprite.modulate.a = 0.0  # initial unsichtbar
	add_child(_icon_sprite)

func _process(delta: float) -> void:
	if _is_overheating:
		_overheat_pulse_time += delta
		var pulse: float = 0.7 + sin(_overheat_pulse_time * 6.0) * 0.3
		bar_sprite.modulate.a = pulse
		if _icon_sprite:
			_icon_sprite.modulate.a = pulse
		return
	
	# Pre-Overheat-Pulse: ab pulse_threshold wird die Bar zunehmend nervöser
	if _current_normalized >= pulse_threshold and visible:
		_pulse_time += delta
		# Pulse-Speed skaliert mit Heat: bei 70% = pulse_speed_low, bei 100% = pulse_speed_high
		var t: float = (_current_normalized - pulse_threshold) / (1.0 - pulse_threshold)
		var speed: float = lerp(pulse_speed_low, pulse_speed_high, clamp(t, 0.0, 1.0))
		# Subtile Intensitäts-Variation, nicht so heftig wie Overheat
		var pulse: float = 0.85 + sin(_pulse_time * speed) * 0.15
		bar_sprite.modulate.a = pulse
		if _icon_sprite:
			_icon_sprite.modulate.a = pulse
	else:
		_pulse_time = 0.0
		# Normale Sichtbarkeit (1.0) wenn nicht im Pulse-Bereich
		if visible and bar_sprite.modulate.a < 1.0 and not _is_overheating:
			bar_sprite.modulate.a = 1.0
			if _icon_sprite:
				_icon_sprite.modulate.a = 1.0


## Hauptmethode: Heat-Wert setzen (0.0 - 1.0 normalisiert)
func set_heat(normalized: float) -> void:
	if _is_overheating:
		return
	
	_current_normalized = normalized
	
	if normalized <= 0.001:
		_hide()
		return
	
	_show()
	
	# Bar-Größe
	fill.size.x = _max_width * normalized
	
	# Farb-Interpolation: blau → gelb (bei 50%) → rot (bei 100%)
	var color: Color
	if normalized < 0.5:
		var t: float = normalized / 0.5
		color = color_low.lerp(color_mid, t)
	else:
		var t: float = (normalized - 0.5) / 0.5
		color = color_mid.lerp(color_high, t)
	
	fill.color = color


func start_overheat() -> void:
	_is_overheating = true
	_overheat_pulse_time = 0.0
	visible = true
	bar_sprite.modulate.a = 1.0
	# Voll mit Overheat-Farbe füllen
	if _icon_sprite:
		_icon_sprite.modulate.a = 1.0
	fill.size.x = _max_width
	fill.color = color_overheat


func end_overheat() -> void:
	_is_overheating = false
	_hide()


func _show() -> void:
	if visible:
		return
	visible = true
	var tween := create_tween()
	tween.tween_property(bar_sprite, "modulate:a", 1.0, fade_in_time)
	if _icon_sprite:
		tween.tween_property(_icon_sprite, "modulate:a", 1.0, fade_in_time)


func _hide() -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(bar_sprite, "modulate:a", 0.0, fade_out_time)
	if _icon_sprite:
		tween.tween_property(_icon_sprite, "modulate:a", 0.0, fade_out_time)
	tween.tween_callback(func():
		visible = false
		fill.size.x = 0
	)
