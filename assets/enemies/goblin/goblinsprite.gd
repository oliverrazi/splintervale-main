extends CharacterBody3D

enum AnimState { IDLE, RUN, HIT }

@export var sprite_path: NodePath = ^"Visual/Sprite"

@onready var sprite: AnimatedSprite3D = get_node(sprite_path)

var anim_state: AnimState = AnimState.IDLE

# Optional: merken, wohin zuletzt geschaut wurde (für Idle ohne Bewegung)
var last_dir: Vector2 = Vector2(0, 1) # Default: "down" (Z+, je nach Welt)

func _physics_process(_delta: float) -> void:
	# Beispiel: anim_state setzen (bei dir kommt RUN/IDLE/HIT vermutlich aus deiner FSM)
	var move_xz := Vector2(velocity.x, velocity.z)

	if anim_state != AnimState.HIT:
		if move_xz.length() > 0.05:
			anim_state = AnimState.RUN
			last_dir = move_xz.normalized()
		else:
			anim_state = AnimState.IDLE

	_apply_animation(anim_state, last_dir)

func play_hit() -> void:
	# Call, wenn der Gegner getroffen wird
	anim_state = AnimState.HIT
	_apply_animation(anim_state, last_dir)

	# Wenn du willst: nach Ende zurück zu Idle/Run (oder per Timer / Anim finished)
	# sprite.animation_finished.connect(...)
	# oder kurzer Timer, je nach Hit-Länge.

func _apply_animation(state: AnimState, dir_xz: Vector2) -> void:
	var d := _dir8_from_vec(dir_xz)
	var base_anim := ""
	var flip := false

	match state:
		AnimState.IDLE:
			var res := _idle_anim_for_dir(d)
			base_anim = res.anim
			flip = res.flip
		AnimState.RUN:
			var res := _run_anim_for_dir(d)
			base_anim = res.anim
			flip = res.flip
		AnimState.HIT:
			var res := _hit_anim_for_dir(d)
			base_anim = res.anim
			flip = res.flip

	# Flip anwenden (horizontales Spiegeln)
	sprite.flip_h = flip

	# Animation nur wechseln, wenn nötig (vermeidet Restart-Flackern)
	if sprite.animation != base_anim:
		sprite.play(base_anim)

func _dir8_from_vec(v: Vector2) -> int:
	# v.x = X, v.y = Z
	# Achtung: In Godot 3D ist oft "vorwärts" = -Z.
	# Hier verwenden wir einfach v.y als Z, passend zu velocity.z.
	if v.length() < 0.001:
		v = last_dir

	var a := atan2(v.y, v.x) # -pi..pi (Z, X)
	# Sektoren: 8
	var sector := int(round(8.0 * a / TAU)) % 8
	# Mapping (0..7) um "Right" herum:
	# 0 Right, 1 UpRight, 2 Up, 3 UpLeft, 4 Left, 5 DownLeft, 6 Down, 7 DownRight
	# ABER: atan2(y,x) mit y=Z: positive Z ist "Down" (aus Kamera-Sicht oft nach unten).
	# Das ist okay, solange du konsistent bleibst.
	return sector

func _idle_anim_for_dir(d: int) -> Dictionary:
	# returns {anim:String, flip:bool}
	match d:
		0: return { "anim": "idle_right", "flip": false }          # Right
		7: return { "anim": "idle_right_bottom", "flip": false }   # DownRight
		6: return { "anim": "idle_bottom", "flip": false }         # Down
		5: return { "anim": "idle_right_bottom", "flip": true }    # DownLeft (mirror)
		4: return { "anim": "idle_right", "flip": true }           # Left (mirror)
		3: return { "anim": "idle_left_top", "flip": false }       # UpLeft
		2: return { "anim": "idle_top", "flip": false }            # Up
		1: return { "anim": "idle_left_top", "flip": true }        # UpRight (mirror)
		_: return { "anim": "idle_bottom", "flip": false }

func _run_anim_for_dir(d: int) -> Dictionary:
	# Du hast Run-Sets: down (11-17) und up (21-27).
	# Deshalb: für "Up-Halbkugel" run_up, sonst run_down.
	match d:
		2, 3, 1: # Up, UpLeft, UpRight
			return { "anim": "run_up", "flip": (d == 1) } # UpRight gespiegelt von UpLeft-Optik
		4: # Left
			return { "anim": "run_down", "flip": true }
		5: # DownLeft
			return { "anim": "run_down", "flip": true }
		0: # Right
			return { "anim": "run_down", "flip": false }
		7: # DownRight
			return { "anim": "run_down", "flip": false }
		6: # Down
			return { "anim": "run_down", "flip": false }
		_:
			return { "anim": "run_down", "flip": false }

func _hit_anim_for_dir(d: int) -> Dictionary:
	match d:
		0: return { "anim": "hit_right", "flip": false }
		7: return { "anim": "hit_right_bottom", "flip": false }
		6: return { "anim": "hit_bottom", "flip": false }
		5: return { "anim": "hit_right_bottom", "flip": true }
		4: return { "anim": "hit_right", "flip": true }
		3: return { "anim": "hit_left_top", "flip": false }
		2: return { "anim": "hit_top", "flip": false }
		1: return { "anim": "hit_left_top", "flip": true }
		_: return { "anim": "hit_bottom", "flip": false }
