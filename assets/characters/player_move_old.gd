extends CharacterBody3D

# --- Steuerung & Physik ---
@export var SPEED: float = 50.0
@export var JUMP_VELOCITY: float = 4.5

# --- Spritesheet-Layout ---
@export var HFRAMES: int = 8           # Spalten
@export var WALK_FRAMES: int = 6       # "6 Kacheln nach rechts"

# --- Animationsgeschwindigkeit ---
@export var WALK_FPS: float = 8.0      # -> langsamer = kleiner, schneller = größer

# --- Zeilenbelegung (0 = oberste Zeile) ---
# Idle (du sagst: Zeilen 1..4), passe diese Werte bei Bedarf im Inspector an:
@export var IDLE_ROW_DOWN: int = 0
@export var IDLE_ROW_UP: int   = 1
@export var IDLE_ROW_SIDE_L: int = 2   # Idle nach links blickend
@export var IDLE_ROW_SIDE_R: int = 2   # Idle nach rechts blickend

# Walk (du sagst: "runter" beginnt in Zeile 5)
@export var WALK_ROW_DOWN: int = 4
@export var WALK_ROW_UP: int   = 5     # <- anpassen, falls bei dir anders
@export var WALK_ROW_SIDE: int = 6     # <- anpassen, falls bei dir anders

# Seitwärts: Nutzt deine Seitwärts-Zeile + Spiegelung?
@export var USE_FLIP_FOR_SIDE: bool = true
# Falls die Seitwärts-Reihe standardmäßig nach LINKS zeigt, bleibt das true.
# Zeigt sie nach rechts, setze SIDE_ROW_IS_LEFT_FACING = false
@export var SIDE_ROW_IS_LEFT_FACING: bool = true

# --- Intern ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_time: float = 0.0            # Zeitakkumulator fürs Laufen
var _is_moving: bool = false
var _last_facing_row: int = 1          # für Idle-Rückkehr
var _last_side_right: bool = false     # für Idle links/rechts

@onready var body:  Sprite3D = $bodysprite
@onready var armor: Sprite3D = $armorsprite
@onready var hair:  Sprite3D = $hairsprite

func _ready() -> void:
	for s in [body, armor, hair]:
		s.hframes = HFRAMES
	# Start-Idle (nach unten)
	_show_idle(IDLE_ROW_DOWN, false)

func _physics_process(delta: float) -> void:
	# Gravity & Jump
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Eingabe (2D) und Weltbewegungsrichtung (3D)
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var world_dir: Vector3 = ($SpringArm3D.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Bewegung anwenden
	if world_dir != Vector3.ZERO:
		velocity.x = world_dir.x * SPEED
		velocity.z = world_dir.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()

	# Animationen aktualisieren
	_update_animation(input_dir, delta)

func _update_animation(dir: Vector2, delta: float) -> void:
	_is_moving = dir != Vector2.ZERO

	if _is_moving:
		# Dominante Achse wählen für Blickrichtung
		var horizontal: bool = abs(dir.x) > abs(dir.y)
		if horizontal:
			# Seitwärts laufen
			var right := dir.x < 0.0
			_last_side_right = right

			# Flip nur wenn wir eine gemeinsame Seiten-Zeile nutzen
			if USE_FLIP_FOR_SIDE:
				# Setze Flip so, dass die Grundausrichtung passt
				# (wenn die Reihe links blickt, dann rechts = flip_h true)
				var flipped := (right if SIDE_ROW_IS_LEFT_FACING else !right)
				_animate_walk(WALK_ROW_SIDE, delta, flipped)
				_last_facing_row = IDLE_ROW_SIDE_R if right else IDLE_ROW_SIDE_L
			else:
				# Ohne Flip: eigene Zeilen für links & rechts verwenden
				var row := WALK_ROW_SIDE  # <- Falls du getrennte Walk-Zeilen hast, ersetze hier!
				_animate_walk(row, delta, false)
				_last_facing_row = IDLE_ROW_SIDE_R if right else IDLE_ROW_SIDE_L
		else:
			# Vertikal laufen
			var row := (WALK_ROW_DOWN if dir.y > 0.0 else WALK_ROW_UP)
			_animate_walk(row, delta, false)
			_last_facing_row = (IDLE_ROW_DOWN if dir.y > 0.0 else IDLE_ROW_UP)
	else:
		# IDLE
		_anim_time = 0.0
		var flipped := (_last_side_right if USE_FLIP_FOR_SIDE else false)
		_show_idle(_last_facing_row, flipped)

func _animate_walk(row: int, delta: float, flipped: bool) -> void:
	# Zeit vorwärts
	_anim_time += delta
	# Basisframe 0..WALK_FRAMES-1 über FPS
	var base: int = int(floor(_anim_time * WALK_FPS)) % WALK_FRAMES
	# Finales Frame = Spalte + Zeilen-Offset
	_apply_frame_to_layers(base, row, flipped)

func _show_idle(row: int, flipped: bool) -> void:
	_apply_frame_to_layers(0, row, flipped)
	
func _apply_frame_to_layers(base: int, row: int, flipped: bool) -> void:
	var frame_index := base + row * HFRAMES
	for s in [body, armor, hair]:
		if s: # falls ein Layer optional fehlt
			s.flip_h = flipped
			s.frame  = frame_index
