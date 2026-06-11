extends Node
class_name PerformanceBenchmark
## Reproduzierbares Performance-Benchmark-Tool für echte Spielszenen.
##
## NUTZUNG:
##   1. Dieses Node in eine Spielszene hängen (oder als Autoload laden).
##   2. record_path_action / playback_action / hud_toggle_action in den
##      Input-Map-Einstellungen anlegen (siehe Konstanten unten) — ODER die
##      Funktionen per Code/Knopf aufrufen.
##   3. RECORD drücken, eine repräsentative Route ablaufen, RECORD stoppen.
##      → Route wird in user://benchmark_route.json gespeichert.
##   4. PLAYBACK drücken: Player wird automatisch die Route entlang bewegt,
##      Metriken werden gesamplet und am Ende als CSV in user:// geschrieben.
##   5. Parameter ändern (z.B. chunk_size), PLAYBACK erneut → CSVs vergleichen.
##
## Das Tool misst engine-weite Render-Metriken — funktioniert daher genauso
## für Bäume, Zäune oder die gesamte Szene, nicht nur für Gras.

# ---- Input-Actions (optional; in Project Settings → Input Map anlegen) ----
const ACTION_RECORD := "benchmark_record"
const ACTION_PLAYBACK := "benchmark_playback"
const ACTION_HUD := "benchmark_hud"

# ---- Konfiguration ----
@export_group("Setup")
## Welches Node bewegt werden soll. Leer = PlayerManager.ensure_player().
@export var target_path: NodePath
## true  = Player-Position abspielen (realistisch, inkl. Kamera-Follow/Occlusion)
## false = Kamera direkt abspielen (isoliert)
@export var playback_moves_player: bool = true
## Aufnahme-Abtastrate in Sekunden (kleiner = feiner, größere Datei).
@export var record_interval: float = 0.05
## Geschwindigkeit beim Abspielen (1.0 = wie aufgenommen).
@export var playback_speed: float = 1.0

@export_group("HUD")
@export var hud_enabled: bool = true
@export var hud_font_size: int = 16

@export_group("Output")
## Verzeichnis für CSV/Route. user:// ist plattformübergreifend beschreibbar.
@export var output_dir: String = "user://benchmark"
## Optionales Label, das in den CSV-Dateinamen wandert (z.B. "chunk8_thin10").
@export var run_label: String = "run"

# ---- Laufzeit-State ----
enum State { IDLE, RECORDING, PLAYING }
var _state: int = State.IDLE

var _target: Node3D
var _route: Array = []              # [{t, pos:Vector3, rot_y:float}]
var _record_accum: float = 0.0
var _record_time: float = 0.0

var _play_index: int = 0
var _play_time: float = 0.0
var _samples: Array = []            # [{t, fps, frame_ms, draw_calls, prims, mem_mb}]

var _hud: CanvasLayer
var _hud_label: Label

# Geglättete HUD-Werte
var _smooth_fps: float = 60.0
var _smooth_frame_ms: float = 16.0


func _ready() -> void:
	_ensure_output_dir()
	_resolve_target()
	if hud_enabled:
		_build_hud()
	set_process(true)
	set_physics_process(true)


func _resolve_target() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null and has_node("/root/PlayerManager"):
		var pm := get_node("/root/PlayerManager")
		if pm.has_method("ensure_player"):
			_target = pm.ensure_player() as Node3D
	if _target == null:
		push_warning("PerformanceBenchmark: kein Target gefunden. "
			+ "target_path setzen oder PlayerManager bereitstellen.")


# ============================================================
#  INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION_RECORD) and event.is_action_pressed(ACTION_RECORD):
		toggle_record()
	if InputMap.has_action(ACTION_PLAYBACK) and event.is_action_pressed(ACTION_PLAYBACK):
		start_playback()
	if InputMap.has_action(ACTION_HUD) and event.is_action_pressed(ACTION_HUD):
		hud_enabled = not hud_enabled
		if _hud:
			_hud.visible = hud_enabled


# ============================================================
#  ÖFFENTLICHE API (auch per Knopf/Code aufrufbar)
# ============================================================

func toggle_record() -> void:
	if _state == State.RECORDING:
		_stop_record()
	else:
		_start_record()

func start_playback() -> void:
	if _state != State.IDLE:
		return
	if not _load_route():
		push_warning("PerformanceBenchmark: keine Route zum Abspielen. Erst aufnehmen.")
		return
	_resolve_target()
	if _target == null:
		return
	_state = State.PLAYING
	_play_index = 0
	_play_time = 0.0
	_samples.clear()
	# Steuerung des Players abklemmen, damit der Benchmark allein bewegt.
	_set_target_external_control(true)
	print("PerformanceBenchmark: Playback gestartet (%d Routenpunkte)" % _route.size())


# ============================================================
#  RECORD
# ============================================================

func _start_record() -> void:
	_resolve_target()
	if _target == null:
		return
	_state = State.RECORDING
	_route.clear()
	_record_accum = 0.0
	_record_time = 0.0
	print("PerformanceBenchmark: Aufnahme gestartet — Route ablaufen, dann erneut RECORD.")

func _stop_record() -> void:
	_state = State.IDLE
	_save_route()
	print("PerformanceBenchmark: Aufnahme gestoppt — %d Punkte gespeichert." % _route.size())


# ============================================================
#  PROCESS
# ============================================================

func _process(delta: float) -> void:
	_update_smooth_metrics(delta)
	if hud_enabled and _hud_label:
		_update_hud()

func _physics_process(delta: float) -> void:
	match _state:
		State.RECORDING:
			_tick_record(delta)
		State.PLAYING:
			_tick_playback(delta)


func _tick_record(delta: float) -> void:
	if _target == null:
		return
	_record_time += delta
	_record_accum += delta
	if _record_accum >= record_interval:
		_record_accum = 0.0
		_route.append({
			"t": _record_time,
			"px": _target.global_position.x,
			"py": _target.global_position.y,
			"pz": _target.global_position.z,
			"ry": _target.global_rotation.y,
		})


func _tick_playback(delta: float) -> void:
	if _target == null or _route.is_empty():
		_finish_playback()
		return

	_play_time += delta * playback_speed

	# Aktuelles Segment finden.
	while _play_index < _route.size() - 1 \
			and float(_route[_play_index + 1]["t"]) <= _play_time:
		_play_index += 1

	if _play_index >= _route.size() - 1:
		_apply_route_point(_route[_route.size() - 1])
		_collect_sample()
		_finish_playback()
		return

	# Zwischen zwei Punkten interpolieren.
	var a: Dictionary = _route[_play_index]
	var b: Dictionary = _route[_play_index + 1]
	var ta: float = a["t"]
	var tb: float = b["t"]
	var span: float = max(tb - ta, 0.0001)
	var f: float = clampf((_play_time - ta) / span, 0.0, 1.0)

	var pos := Vector3(
		lerpf(a["px"], b["px"], f),
		lerpf(a["py"], b["py"], f),
		lerpf(a["pz"], b["pz"], f))
	var ry := lerp_angle(a["ry"], b["ry"], f)

	if playback_moves_player:
		_target.global_position = pos
		_target.global_rotation.y = ry
		if _target is CharacterBody3D:
			(_target as CharacterBody3D).velocity = Vector3.ZERO
	else:
		# Kamera-Modus: aktive Kamera direkt setzen.
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.global_position = pos

	_collect_sample()


func _apply_route_point(point: Dictionary) -> void:
	if _target == null:
		return
	var pos := Vector3(point["px"], point["py"], point["pz"])
	var ry: float = point["ry"]
	if playback_moves_player:
		_target.global_position = pos
		_target.global_rotation.y = ry
		if _target is CharacterBody3D:
			(_target as CharacterBody3D).velocity = Vector3.ZERO
	else:
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.global_position = pos


func _collect_sample() -> void:
	_samples.append({
		"t": _play_time,
		"fps": Engine.get_frames_per_second(),
		"frame_ms": _smooth_frame_ms,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"vmem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	})


func _finish_playback() -> void:
	_state = State.IDLE
	_set_target_external_control(false)
	var path := _write_csv()
	_print_summary(path)


# ============================================================
#  PLAYER-STEUERUNG ABKLEMMEN
#  Verhindert, dass dein Movement-Script gegen den Benchmark arbeitet.
#  Erwartet optional eine bool-Property/Methode am Player. Greift defensiv,
#  falls nicht vorhanden — dann wird nur die Position überschrieben.
# ============================================================

func _set_target_external_control(active: bool) -> void:
	if _target == null:
		return
	# Bevorzugt eine Methode set_external_control(bool) am Player.
	if _target.has_method("set_external_control"):
		_target.call("set_external_control", active)
		return
	# Fallback: eine bool-Property 'external_control', falls vorhanden.
	if "external_control" in _target:
		_target.set("external_control", active)
		return
	# Sonst: Physik-Process des Players pausieren, damit Movement nicht stört.
	# (Kamera bleibt aktiv, da sie ein eigenes Node ist.)
	_target.set_physics_process(not active)


# ============================================================
#  ROUTE SPEICHERN / LADEN
# ============================================================

func _route_file() -> String:
	return output_dir.path_join("benchmark_route.json")

func _save_route() -> void:
	var f := FileAccess.open(_route_file(), FileAccess.WRITE)
	if f == null:
		push_warning("PerformanceBenchmark: Route konnte nicht gespeichert werden.")
		return
	f.store_string(JSON.stringify(_route))
	f.close()

func _load_route() -> bool:
	var path := _route_file()
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return false
	_route = data
	return true


# ============================================================
#  CSV-EXPORT + ZUSAMMENFASSUNG
# ============================================================

func _ensure_output_dir() -> void:
	var abs := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(abs)

func _write_csv() -> String:
	if _samples.is_empty():
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var fname := "%s_%s.csv" % [run_label, stamp]
	var path := output_dir.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("PerformanceBenchmark: CSV konnte nicht geschrieben werden.")
		return ""
	f.store_line("time,fps,frame_ms,draw_calls,primitives,render_objects,vmem_mb")
	for s in _samples:
		f.store_line("%.3f,%.1f,%.3f,%d,%d,%d,%.1f" % [
			s["t"], s["fps"], s["frame_ms"],
			int(s["draw_calls"]), int(s["prims"]),
			int(s["objects"]), s["vmem_mb"]])
	f.close()
	return path


func _print_summary(csv_path: String) -> void:
	if _samples.is_empty():
		print("PerformanceBenchmark: keine Samples erfasst.")
		return

	var fps_arr: Array[float] = []
	var ms_arr: Array[float] = []
	var dc_max := 0
	var prim_max := 0
	for s in _samples:
		fps_arr.append(s["fps"])
		ms_arr.append(s["frame_ms"])
		dc_max = max(dc_max, int(s["draw_calls"]))
		prim_max = max(prim_max, int(s["prims"]))

	fps_arr.sort()
	ms_arr.sort()

	var n := fps_arr.size()
	var fps_avg := 0.0
	for v in fps_arr: fps_avg += v
	fps_avg /= n

	# 1% low = Durchschnitt des schlechtesten Prozents (aussagekräftiger als min)
	var one_pct_count: int = max(1, int(n * 0.01))
	var low_sum := 0.0
	for i in one_pct_count:
		low_sum += fps_arr[i]
	var fps_1pct_low := low_sum / one_pct_count

	# 95th percentile frame time (Worst-Case ohne Ausreißer)
	var p95_idx: int = clampi(int(n * 0.95), 0, n - 1)
	var ms_p95 := ms_arr[p95_idx]

	print("\n========== BENCHMARK: %s ==========" % run_label)
	print("Samples:        %d" % n)
	print("FPS avg:        %.1f" % fps_avg)
	print("FPS 1%% low:     %.1f" % fps_1pct_low)
	print("Frame ms p95:   %.2f  (Worst-Case-Frame ohne Ausreißer)" % ms_p95)
	print("Draw calls max: %d" % dc_max)
	print("Primitives max: %d  (= Dreiecke·3 grob)" % prim_max)
	print("CSV:            %s" % ProjectSettings.globalize_path(csv_path))
	print("======================================\n")


# ============================================================
#  HUD
# ============================================================

func _update_smooth_metrics(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var frame_ms := delta * 1000.0
	_smooth_fps = lerpf(_smooth_fps, fps, 0.1)
	_smooth_frame_ms = lerpf(_smooth_frame_ms, frame_ms, 0.1)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 128
	add_child(_hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.modulate = Color(1, 1, 1, 0.9)
	_hud.add_child(panel)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", hud_font_size)
	_hud_label.add_theme_constant_override("line_spacing", 2)
	panel.add_child(_hud_label)

func _update_hud() -> void:
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var vmem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	var state_str := ""
	match _state:
		State.RECORDING: state_str = "  ● REC (%d)" % _route.size()
		State.PLAYING:   state_str = "  ▶ PLAY (%d/%d)" % [_play_index, _route.size()]

	_hud_label.text = "FPS  %.0f   (%.2f ms)%s\nDraw calls   %d\nPrimitives   %s\nObjects      %d\nVRAM         %.0f MB" % [
		_smooth_fps, _smooth_frame_ms, state_str,
		dc, _format_thousands(prims), objs, vmem]

func _format_thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out
