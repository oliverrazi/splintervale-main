extends Node

# Hit Stop
var _hitstop_timer: float = 0.0

# Camera Shake
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0

# Camera Zoom
var _zoom_amount: float = 0.0
var _zoom_duration: float = 0.0
var _zoom_timer: float = 0.0
var _original_fov: float = 0.0
var _camera: Camera3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Läuft auch während Pause


func _process(delta: float) -> void:
	_process_hitstop(delta)
	_process_shake(delta)
	_process_zoom(delta)


# ============ HIT STOP ============

func hitstop(duration: float = 0.1) -> void:
	_hitstop_timer = duration
	get_tree().paused = true


func _process_hitstop(delta: float) -> void:
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0:
			get_tree().paused = false


# ============ CAMERA SHAKE ============

func shake(intensity: float = 0.3, duration: float = 0.2) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration
	
	if _camera == null:
		_camera = get_viewport().get_camera_3d()


func _process_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		return
	
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	
	_shake_timer -= delta
	
	# Shake Intensität nimmt ab über Zeit
	var progress: float = _shake_timer / _shake_duration
	var current_intensity: float = _shake_intensity * progress
	
	# Zufällige Offset
	var offset := Vector3(
		randf_range(-current_intensity, current_intensity),
		randf_range(-current_intensity, current_intensity),
		0.0
	)
	
	# Wende Shake auf Camera an (lokaler Offset)
	_camera.h_offset = offset.x
	_camera.v_offset = offset.y
	
	# Reset wenn fertig
	if _shake_timer <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


# ============ CAMERA ZOOM ============

func zoom(amount: float = 5.0, duration: float = 0.15) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	
	# Speichere original FOV nur wenn kein Zoom aktiv
	if _zoom_timer <= 0.0:
		_original_fov = _camera.fov
	
	_zoom_amount = amount
	_zoom_duration = duration
	_zoom_timer = duration


func _process_zoom(delta: float) -> void:
	if _zoom_timer <= 0.0:
		return
	
	if _camera == null:
		return
	
	_zoom_timer -= delta
	
	# Zoom rein und dann zurück (ping-pong)
	var progress: float = _zoom_timer / _zoom_duration
	var zoom_curve: float = sin(progress * PI)  # 0 -> 1 -> 0
	
	_camera.fov = _original_fov - (_zoom_amount * zoom_curve)
	
	# Reset wenn fertig
	if _zoom_timer <= 0.0:
		_camera.fov = _original_fov


# ============ COMBO FUNKTION ============

func hit_effect(hitstop_duration: float = 0.15, shake_intensity: float = 0.03, shake_duration: float = 0.15, zoom_amount: float = 1.0, zoom_duration: float = 1.1) -> void:
	hitstop(hitstop_duration)
	shake(shake_intensity, shake_duration)
	zoom(zoom_amount, zoom_duration)
