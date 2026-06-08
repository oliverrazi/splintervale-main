extends CanvasLayer
## Bildschirmrand-Vignette, die einsetzt, wenn HP unter `hp_threshold`
## fallen UND der Player im Kampf ist.
##
## Als Autoload registrieren (Name: LowHpVignette). KEIN class_name hier,
## weil das mit dem Autoload-Namen kollidiert.
##
## Trennung der zwei Steuerquellen:
##   - _fade_alpha     (0..1): wird vom Combat-Signal getweent
##   - _hp_intensity   (0..1): wird aus HP% abgeleitet, sanft geglättet
##   - Shader-Intensity = _fade_alpha * _hp_intensity
## So koennen sich beide unabhaengig aendern, ohne dass es ruckelt.

@export var vignette_shader: Shader

@export_group("Schwelle")
## Ab welchem HP-Prozentsatz die Vignette einsetzt (Default 20%).
@export_range(0.0, 1.0) var hp_threshold: float = 0.2
## Maximale Intensitaet bei 0% HP.
@export_range(0.0, 1.0) var max_intensity: float = 0.85

@export_group("Look")
@export var tint_color: Color = Color(0.85, 0.05, 0.05)
@export_range(0.0, 0.71) var vignette_radius: float = 0.32
@export_range(0.05, 0.6) var vignette_softness: float = 0.3
@export_range(0.0, 1.0) var noise_strength: float = 0.5
@export var noise_scale: float = 3.0
@export var noise_speed: float = 0.5

@export_group("Heartbeat")
## Pulsfrequenz bei der Schwelle (Hz). Langsame, ruhige Atmung.
@export_range(0.1, 3.0) var min_pulse_freq: float = 0.5
## Pulsfrequenz bei 0% HP (Hz). Echte Panik.
@export_range(0.1, 5.0) var max_pulse_freq: float = 1.8
## Wie tief der Puls die Vignette moduliert.
@export_range(0.0, 1.0) var pulse_depth: float = 0.35

@export_group("Fades")
@export var fade_in_duration: float = 0.6
@export var fade_out_duration: float = 1.0

@export_group("Rendering")
## CanvasLayer-Index. Hoeher als HUD (50) und HD2DPostProcess (10),
## damit die Vignette ueber allem liegt – aber unter Cutscene-Fades.
@export var vignette_layer: int = 60

var _rect: ColorRect
var _mat: ShaderMaterial

var _fade_alpha: float = 0.0          ## 0 = aus, 1 = an (Combat-Toggle)
var _hp_intensity_target: float = 0.0 ## Roh-Intensitaet aus HP%
var _hp_intensity: float = 0.0        ## geglaettet
var _current_hp_percent: float = 1.0
var _pulse_time: float = 0.0
var _fade_tween: Tween
var _debug_override: bool = false


func _ready() -> void:
	# Im Pause-Modus weiterlaufen (Battle-Pause haelt Musik+Vignette aktiv).
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = vignette_layer

	_build_overlay()

	# CombatManager: Sichtbarkeit
	if get_node_or_null("/root/CombatManager"):
		if not CombatManager.combat_started.is_connected(_on_combat_started):
			CombatManager.combat_started.connect(_on_combat_started)
		if not CombatManager.combat_ended.is_connected(_on_combat_ended):
			CombatManager.combat_ended.connect(_on_combat_ended)
	else:
		push_warning("LowHpVignette: CombatManager-Autoload nicht gefunden.")

	# PlayerData: HP-Aenderungen
	call_deferred("_connect_player_data")


func _build_overlay() -> void:
	_rect = ColorRect.new()
	_rect.name = "VignetteRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	# Schutz: Ohne Shader wuerde das weisse ColorRect den ganzen Bildschirm
	# decken. Lieber deaktivieren und in der Konsole anzeigen, was fehlt.
	if vignette_shader == null:
		_rect.visible = false
		push_warning("LowHpVignette: kein vignette_shader zugewiesen – Vignette deaktiviert.\n" +
			"Tipp: als Autoload eine .tscn registrieren (siehe Anleitung), " +
			"nicht das .gd-Script direkt.")
		return

	_mat = ShaderMaterial.new()
	_mat.shader = vignette_shader
	_push_static_params()
	_rect.material = _mat


func _push_static_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("tint_color", tint_color)
	_mat.set_shader_parameter("vignette_radius", vignette_radius)
	_mat.set_shader_parameter("vignette_softness", vignette_softness)
	_mat.set_shader_parameter("noise_strength", noise_strength)
	_mat.set_shader_parameter("noise_scale", noise_scale)
	_mat.set_shader_parameter("noise_speed", noise_speed)
	_mat.set_shader_parameter("pulse_depth", pulse_depth)
	_mat.set_shader_parameter("intensity", 0.0)
	_mat.set_shader_parameter("pulse", 0.0)


func _connect_player_data() -> void:
	# Auf GameManager + PlayerData warten (kann beim allerersten Frame
	# noch nicht ready sein).
	var tries := 0
	while tries < 30:
		if has_node("/root/GameManager"):
			var gm = get_node("/root/GameManager")
			if "player_data" in gm and gm.player_data != null:
				var pd: PlayerData = gm.player_data
				if not pd.hp_changed.is_connected(_on_hp_changed):
					pd.hp_changed.connect(_on_hp_changed)
				_current_hp_percent = float(pd.current_hp) / maxf(float(pd.max_hp), 1.0)
				_update_hp_intensity()
				return
		await get_tree().process_frame
		tries += 1
	push_warning("LowHpVignette: GameManager.player_data nach 30 Frames nicht verfügbar.")


# ---------------------------------------------------------------------
#  Signal-Handler
# ---------------------------------------------------------------------

func _on_combat_started() -> void:
	_fade_to(1.0, fade_in_duration)


func _on_combat_ended() -> void:
	_fade_to(0.0, fade_out_duration)


func _on_hp_changed(current: int, maximum: int) -> void:
	_current_hp_percent = float(current) / maxf(float(maximum), 1.0)
	_update_hp_intensity()


# ---------------------------------------------------------------------
#  Logik
# ---------------------------------------------------------------------

func _update_hp_intensity() -> void:
	if _current_hp_percent >= hp_threshold:
		_hp_intensity_target = 0.0
		return
	# 0..1 ueber den Schwellenbereich, mit beschleunigender Kurve.
	# Bei 20% -> 0, bei 10% -> ~0.62, bei 5% -> ~0.81, bei 0% -> 1.
	var t: float = 1.0 - (_current_hp_percent / maxf(hp_threshold, 0.001))
	_hp_intensity_target = pow(clampf(t, 0.0, 1.0), 0.7) * max_intensity


func _fade_to(target: float, duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(_set_fade_alpha, _fade_alpha, target, duration)


func _set_fade_alpha(v: float) -> void:
	_fade_alpha = v


func _process(delta: float) -> void:
	# Debug-Override: Werte stehen lassen, nicht ueberschreiben.
	if _debug_override:
		return

	# HP-Intensitaet glaetten – verhindert harte Spruenge bei groesseren
	# Heals/Treffern. Die Rate (4.0) ist framerate-unabhaengig.
	_hp_intensity = lerpf(_hp_intensity, _hp_intensity_target,
		minf(4.0 * delta, 1.0))

	# Pulsfrequenz haengt am aktuellen HP-Stand (nicht am Target),
	# damit der Puls beim Heilen sofort langsamer wird.
	_pulse_time += delta
	var hp_t: float = 1.0 - clampf(_current_hp_percent / maxf(hp_threshold, 0.001), 0.0, 1.0)
	var freq: float = lerpf(min_pulse_freq, max_pulse_freq, hp_t)
	var pulse: float = (sin(_pulse_time * freq * TAU) + 1.0) * 0.5  # 0..1

	if _mat:
		_mat.set_shader_parameter("intensity", _fade_alpha * _hp_intensity)
		_mat.set_shader_parameter("pulse", pulse)


# ---------------------------------------------------------------------
#  Test-/Debug-API
# ---------------------------------------------------------------------

## Praktisch beim Tuning: forciert die Vignette unabhängig vom State.
## debug_force_show(0.85) zeigt sie dauerhaft, bis debug_clear() kommt.
func debug_force_show(intensity_value: float, pulse_value: float = 1.0) -> void:
	_debug_override = true
	if _rect:
		_rect.visible = true
	if _mat:
		_mat.set_shader_parameter("intensity", clampf(intensity_value, 0.0, 1.0))
		_mat.set_shader_parameter("pulse", clampf(pulse_value, 0.0, 1.0))
	else:
		push_warning("LowHpVignette.debug_force_show: kein Material – Shader fehlt?")


## Override aufheben, zurueck zum normalen HP/Combat-gesteuerten Verhalten.
func debug_clear() -> void:
	_debug_override = false
	if _rect and _mat:
		_rect.material = _mat
		_rect.color = Color.WHITE


## BRUTAL-TEST: faerbt das Rect hart halbrot, OHNE Shader. Wenn danach
## der halbe Bildschirm rot ist, funktionieren CanvasLayer + Rect + Tree.
## Wenn NICHTS passiert, liegt das Problem im Setup (Rect rendert nicht).
## Mit debug_clear() wieder zuruecksetzen.
func debug_force_solid() -> void:
	_debug_override = true
	if _rect == null:
		push_warning("LowHpVignette.debug_force_solid: _rect ist null – _ready() lief nicht?")
		return
	_rect.visible = true
	_rect.material = null               # Shader umgehen
	_rect.color = Color(1.0, 0.0, 0.0, 0.5)
	print("[LowHpVignette] debug_force_solid aktiv. layer=%d, rect_size=%s, visible=%s"
		% [layer, str(_rect.size), str(visible)])
