class_name LadderComponent
extends Node

@export_group("Klettern")
@export var climb_speed: float = 0.6          ## m/s — bei 0.3m-Playerscale bewusst langsam
@export var exit_margin: float = 0.02          ## Toleranz an den Grenzen
@export var remount_cooldown: float = 0.25     ## Anti-Flacker-Sicherheitsnetz
@export var top_exit_duration: float = 0.18    ## Tween-Dauer für den Ausstieg oben

@export_group("Animation")
@export var climb_frames: Array[int] = [110, 111, 112, 113]  ## 4 Frames, Reihenfolge = Zyklus
@export var step_distance: float = 0.05        ## Kletterdistanz pro Animationsschritt (Meter)

var _player: CharacterBody3D
var _character: Node = null

var _nearby_ladder: Ladder = null   # ClimbZone-Registrierung
var _top_ladder: Ladder = null      # TopZone-Registrierung
var _ladder: Ladder = null          # aktive Leiter während des Kletterns

var _is_climbing: bool = false
var _is_exiting: bool = false
var _cooldown: float = 0.0
var _anim_distance: float = 0.0
var _anim_index: int = 0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_character = _player.get_node_or_null("charactersprite")


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func is_active() -> bool:
	return _is_climbing


# ─── Registrierung (von Ladder-Areas aufgerufen) ───

func set_nearby_ladder(l: Ladder) -> void:
	_nearby_ladder = l

func clear_nearby_ladder(l: Ladder) -> void:
	if _nearby_ladder == l:
		_nearby_ladder = null

func set_top_ladder(l: Ladder) -> void:
	_top_ladder = l

func clear_top_ladder(l: Ladder) -> void:
	if _top_ladder == l:
		_top_ladder = null


# ─── Mounting ───

func try_mount(input_dir: Vector2) -> bool:
	if _is_climbing or _cooldown > 0.0:
		return false

	# Von unten/mittig: Hoch drücken in der ClimbZone
	# (input_dir.y < 0 == "move_up" bei eurem Input-Vector)
	if _nearby_ladder and input_dir.y < -0.5:
		# Nur mounten, wenn überhaupt noch Kletterstrecke nach oben existiert
		if _player.global_position.y < _nearby_ladder.get_top_y() - exit_margin:
			_mount(_nearby_ladder, false)
			return true

	# Von oben: Runter drücken in der TopZone
	if _top_ladder and input_dir.y > 0.5:
		_mount(_top_ladder, true)
		return true

	return false


func _mount(ladder: Ladder, at_top: bool) -> void:
	_ladder = ladder
	_is_climbing = true
	_is_exiting = false
	_anim_distance = 0.0
	_anim_index = 0

	_player.velocity = Vector3.ZERO

	# Auf die Kletterlinie snappen
	var line: Vector3 = ladder.get_line_position()
	var p: Vector3 = _player.global_position
	p.x = line.x
	p.z = line.z
	if at_top:
		p.y = ladder.get_top_y()
	else:
		p.y = clampf(p.y, ladder.get_bottom_y(), ladder.get_top_y())
	_player.global_position = p

	_apply_climb_frame()


# ─── Kletter-Loop (vom Player in _physics_process aufgerufen) ───

func process_climb(delta: float) -> void:
	if _is_exiting:
		return  # Tween läuft, keine Eingriffe

	var climb: float = Input.get_axis("move_down", "move_up")  # +1 = hoch
	var bottom_y: float = _ladder.get_bottom_y()
	var top_y: float = _ladder.get_top_y()
	var p: Vector3 = _player.global_position

	# ── Ausstieg oben: NUR bei aktivem Hoch-Input an der Oberkante ──
	if climb > 0.1 and p.y >= top_y - exit_margin:
		_start_top_exit()
		return

	# ── Ausstieg unten: NUR bei aktivem Runter-Input an der Unterkante ──
	if climb < -0.1 and p.y <= bottom_y + exit_margin:
		_dismount_bottom()
		return

	# ── Bewegung: kinematisch, hart geclampt — kein move_and_slide ──
	var dy: float = climb * climb_speed * delta
	p.y = clampf(p.y + dy, bottom_y, top_y)

	var line: Vector3 = _ladder.get_line_position()
	p.x = line.x
	p.z = line.z
	_player.global_position = p
	_player.velocity = Vector3.ZERO

	_advance_animation(absf(dy))


# ─── Animation: 2 Frames × 4 Schritte, Schritt 3+4 gespiegelt ───
# Der Zyklus ist distanzgetrieben, nicht zeitgetrieben:
# Die Hände greifen sichtbar pro zurückgelegter Strecke — kein Sliding.

func _advance_animation(distance: float) -> void:
	if climb_frames.is_empty():
		return
	_anim_distance += distance / 3
	while _anim_distance >= step_distance:
		_anim_distance -= step_distance
		_anim_index = (_anim_index + 1) % climb_frames.size()
		_apply_climb_frame()


func _apply_climb_frame() -> void:
	if _character == null or climb_frames.is_empty():
		return
	_character.frame = climb_frames[_anim_index % climb_frames.size()]
	_character.flip_h = false


# ─── Ausstiege ───

func _start_top_exit() -> void:
	_is_exiting = true
	_player._last_dir_mode = _player.DirMode.UP  # Rückenansicht auf dem Ledge

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_player, "global_position", _ladder.get_top_exit_position(), top_exit_duration)
	tween.finished.connect(_finish_climb)


func _dismount_bottom() -> void:
	_player._last_dir_mode = _player.DirMode.DOWN
	_finish_climb()


func _finish_climb() -> void:
	_is_climbing = false
	_is_exiting = false
	_ladder = null
	_cooldown = remount_cooldown
	_player.velocity = Vector3.ZERO
	_player._show_idle()


func cancel() -> void:
	## Für Damage, Drowning, Cinematics — bricht hart ab, Gravity übernimmt danach
	if not _is_climbing:
		return
	_is_climbing = false
	_is_exiting = false
	_ladder = null
	_cooldown = remount_cooldown
