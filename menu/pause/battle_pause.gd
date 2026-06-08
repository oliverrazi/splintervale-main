extends CanvasLayer
## Kampf-/Cutscene-Pause im FF-Stil.
##
## Als Autoload registrieren (Name: BattlePause). KEIN class_name.
##
## Verhalten:
##   - Faengt Escape (ui_cancel) per _input() ab – das laeuft VOR dem
##     _unhandled_input des normalen Pause-Menues. Dadurch:
##       * im Kampf ODER in einer Cutscene -> Kampf-Pause (dieses Overlay)
##       * sonst -> Event durchgelassen -> normales Menue oeffnet wie bisher
##   - Abgedunkelter Hintergrund + "Pause"-Text mittig (CI-Font).
##   - Musik wird pausiert (nicht gestoppt) und beim Fortsetzen weitergespielt.
##   - get_tree().paused = true friert Gameplay UND Cutscene ein; dieses
##     Overlay laeuft via PROCESS_MODE_ALWAYS weiter.

const TITLE_FONT_PATH: String = "res://menu/assets/fonts/Cinzel-Bold.ttf"

@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.6)
@export var fade_duration: float = 0.25
@export var pause_text: String = "Pause"
@export var vignette_layer_index: int = 70   ## ueber HUD(50)/Vignette(60)
## Temporaer zum Debuggen: zeigt bei jedem Escape den State im Output.
@export var debug_log: bool = true

var _root: Control
var _dim: ColorRect
var _label: Label
var _is_paused: bool = false
var _fade_tween: Tween

# Wird vom CutsceneDirector gesetzt, damit Escape auch in Cutscenes
# die Kampf-Pause statt des Menues oeffnet.
var _cutscene_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = vignette_layer_index
	_build_overlay()
	_connect_scene_transition()


## Sicherheitsnetz gegen ein haengendes _cutscene_active-Flag: Wenn eine
## Cutscene per Szenenwechsel endet (statt ueber _exit_cinematic), wuerde
## das Flag sonst true bleiben und Escape ueberall abfangen. Bei jedem
## abgeschlossenen Szenenwechsel setzen wir es darum hart zurueck.
func _connect_scene_transition() -> void:
	var st := get_node_or_null("/root/SceneTransition")
	if st == null:
		return
	if st.has_signal("scene_transition_completed"):
		if not st.scene_transition_completed.is_connected(_on_scene_transition_completed):
			st.scene_transition_completed.connect(_on_scene_transition_completed)


func _on_scene_transition_completed() -> void:
	_cutscene_active = false
	# Falls beim Wechsel noch eine Kampf-Pause offen war: aufloesen.
	if _is_paused:
		_is_paused = false
		_root.visible = false
		_root.modulate.a = 0.0
		get_tree().paused = false


func _build_overlay() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = dim_color
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_label = Label.new()
	_label.text = pause_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# CI-Font-Stil (identisch zum Boss-Namen)
	_label.add_theme_font_size_override("font_size", 58)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 3)
	if ResourceLoader.exists(TITLE_FONT_PATH):
		_label.add_theme_font_override("font", load(TITLE_FONT_PATH) as FontFile)
	center.add_child(_label)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel", false):
		return

	if debug_log:
		var in_combat := false
		var has_cm := has_node("/root/CombatManager")
		if has_cm:
			in_combat = CombatManager.is_in_combat()
		var n_enemies := 0
		if has_cm:
			n_enemies = CombatManager.get_engaged_enemies().size()
		print("[BattlePause] ESC | has_CombatManager=%s in_combat=%s engaged=%d cutscene=%s intercept=%s paused=%s"
			% [has_cm, in_combat, n_enemies, _cutscene_active, _should_intercept(), _is_paused])

	# Wenn bereits in Kampf-Pause: fortsetzen.
	if _is_paused:
		resume()
		get_viewport().set_input_as_handled()
		return

	# Nicht eingreifen, wenn ein Dialog laeuft (gleiche Regel wie Pause-Menue).
	var dm: Node = get_node_or_null("/root/DialogueManager")
	if dm and (dm.is_dialogue_active() or dm.is_on_cooldown()):
		return

	# Nur eingreifen, wenn Kampf ODER Cutscene aktiv ist.
	if _should_intercept():
		open()
		get_viewport().set_input_as_handled()
	# sonst: Event NICHT handeln -> _unhandled_input des Pause-Menues uebernimmt.


func _should_intercept() -> bool:
	if _cutscene_active:
		return true
	if has_node("/root/CombatManager"):
		return CombatManager.is_in_combat()
	return false


# ---------------------------------------------------------------------
#  OEffnen / Schliessen
# ---------------------------------------------------------------------

func open() -> void:
	if _is_paused:
		return
	_is_paused = true

	# Musik anhalten (weiterspielbar). Methode im MusicManager ergaenzen.
	if has_node("/root/MusicManager") and MusicManager.has_method("pause_music"):
		MusicManager.pause_music()

	_root.visible = true
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 1.0, fade_duration)

	get_tree().paused = true


func resume() -> void:
	if not _is_paused:
		return
	_is_paused = false

	# Spiel zuerst entpausieren, damit Tweens etc. wieder laufen.
	get_tree().paused = false

	if has_node("/root/MusicManager") and MusicManager.has_method("resume_music"):
		MusicManager.resume_music()

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, fade_duration)
	_fade_tween.tween_callback(func(): _root.visible = false)


func is_paused() -> bool:
	return _is_paused


## Vom CutsceneDirector aufrufen: true beim Cutscene-Start, false am Ende.
func set_cutscene_active(active: bool) -> void:
	_cutscene_active = active
