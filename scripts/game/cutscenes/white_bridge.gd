extends CanvasLayer
## Persistentes weisses Overlay, das einen Szenenwechsel ueberlebt.
##
## Als Autoload registrieren (Name: WhiteBridge). KEIN class_name.
##
## Zweck: Die Intro-Cutscene endet im Weiss. Beim Wechsel zu demo.tscn darf
## kein einziger Frame ohne Weiss liegen, sonst blitzt Wald/Schwarz durch.
## Dieses Overlay liegt auf einem eigenen, sehr hohen CanvasLayer und wird
## NICHT von der Szene zerstoert (Autoload). Ablauf:
##   1. Intro ruft WhiteBridge.cover_instant() kurz vor dem Szenenwechsel.
##   2. Szenenwechsel passiert — das Weiss bleibt liegen.
##   3. Der WakeUpDirector in demo.tscn ruft WhiteBridge.fade_out(dauer).

@export var layer_index: int = 128   ## ueber wirklich allem
@export var cover_color: Color = Color(1, 1, 1, 1)

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = layer_index
	_build_overlay()


func _build_overlay() -> void:
	_rect = ColorRect.new()
	_rect.name = "WhiteRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(cover_color.r, cover_color.g, cover_color.b, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


## Sofort komplett decken (kein Fade). Vor dem Szenenwechsel aufrufen.
func cover_instant() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rect.visible = true
	_rect.color = Color(cover_color.r, cover_color.g, cover_color.b, 1.0)


## Sanft einblenden (falls du das Weiss selbst hochfahren willst statt
## es von der Intro-Vignette uebernehmen zu lassen).
func cover(duration: float = 0.5) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rect.visible = true
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 1.0, duration)


## Weiss ausblenden. Vom WakeUpDirector in demo.tscn aufgerufen.
func fade_out(duration: float = 1.2) -> void:
	if not _rect.visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_rect, "color:a", 0.0, duration)
	_tween.tween_callback(func(): _rect.visible = false)


func is_covering() -> bool:
	return _rect.visible and _rect.color.a > 0.0
