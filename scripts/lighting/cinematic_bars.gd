extends Control
class_name CinematicBars
## Zwei Letterbox-Balken (oben/unten), die filmisch ein- und ausfahren.
##
## Szenenaufbau (Kinder dieses Control):
##   CinematicBars (Control, Full Rect, Mouse Filter = Ignore)
##     ├── Top    (ColorRect, schwarz)
##     └── Bottom (ColorRect, schwarz)
##
## Höhe der Balken über die Property `bar_height` animierbar.

@onready var _top: ColorRect = $Top
@onready var _bottom: ColorRect = $Bottom

var bar_height: float = 0.0:
	set(value):
		bar_height = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply()


func _apply() -> void:
	# Oberer Balken: am oberen Rand verankert, wächst nach unten.
	_top.anchor_left = 0.0
	_top.anchor_right = 1.0
	_top.anchor_top = 0.0
	_top.anchor_bottom = 0.0
	_top.offset_left = 0.0
	_top.offset_right = 0.0
	_top.offset_top = 0.0
	_top.offset_bottom = bar_height

	# Unterer Balken: am unteren Rand verankert, wächst nach oben.
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_left = 0.0
	_bottom.offset_right = 0.0
	_bottom.offset_top = -bar_height
	_bottom.offset_bottom = 0.0


func show_bars(height: float, duration: float) -> void:
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "bar_height", height, duration)
	await t.finished


func hide_bars(duration: float) -> void:
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(self, "bar_height", 0.0, duration)
	await t.finished
