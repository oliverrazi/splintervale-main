extends CharacterBody3D

@onready var sprite: Sprite3D = $Sprite3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# === Spritesheet-Layout ===
const HFRAMES: int = 8                 # Spalten (aus deiner Szene)
const VFRAMES: int = 8                 # Zeilen  (aus deiner Szene)
const FRAMES_PER_WALK: int = 6         # Anzahl Walk-Frames in einer Zeile

# Welche Zeile zeigt welche Richtung?
# Passe diese 3 Konstanten an dein Sheet an:
const ROW_DOWN  := 0                   # z.B. Zeile 0 = nach unten
const ROW_UP    := 1                   # z.B. Zeile 1 = nach oben
const ROW_SIDE  := 2                   # z.B. Zeile 2 = seitlich (links/rechts via flip_h)

var _last_anim: StringName = &""

func _ready() -> void:
	# Sicherstellen, dass Sprite3D die korrekten Frames hat
	sprite.hframes = HFRAMES
	sprite.vframes = VFRAMES
	# Optional: Start-Idle
	_set_idle(ROW_DOWN)

func handle_walk_animation(direction: Vector2) -> void:
	# 1) Idle
	if direction == Vector2.ZERO:
		if anim_player.is_playing():
			anim_player.stop()
		_set_idle(_row_from_direction(Vector2(0, 1))) # Idle nach unten (anpassbar)
		return

	# 2) Richtung bestimmen
	var row := _row_from_direction(direction)

	# 3) Seitenspiegelung für rechts/links
	if abs(direction.x) > abs(direction.y):
		# Seitliche Reihe; rechts = flip_h true (falls dein Sheet „links“ zeigt)
		sprite.flip_h = direction.x > 0
	else:
		sprite.flip_h = false

	# 4) Walk-Animation starten (nur einmal)
	if _last_anim != &"walk" or !anim_player.is_playing():
		if anim_player.has_animation("walk"):
			anim_player.play("walk")
			_last_anim = &"walk"

	# 5) Basisframe 0..FRAMES_PER_WALK-1 bestimmen
	#    Variante A (empfohlen): Wenn dein "Sprite3D:frame"-Track 0..5 keyt, kannst du ihn direkt lesen:
	#    var base := sprite.frame % HFRAMES
	#    Variante B (robust, unabhängig von Tracks): aus Zeit berechnen:
	var base := _compute_base_frame()

	# 6) Zeilen-Offset anwenden
	sprite.frame = base + (row * HFRAMES)

func _row_from_direction(dir: Vector2) -> int:
	# Dominante Achse wählen (klassisch fürs Laufen)
	if abs(dir.x) > abs(dir.y):
		return ROW_SIDE
	return ROW_DOWN if dir.y > 0 else ROW_UP

func _set_idle(row: int) -> void:
	# Spalte 0 als Idlesa
	sprite.frame = (row * HFRAMES)

func _compute_base_frame() -> int:
	# Rechnet den Basisframe aus der aktuellen Animationszeit (unabhängig von Keyframes)
	if !anim_player.has_animation("walk"):
		return 0
	var a: Animation = anim_player.get_animation("walk")
	if a.length <= 0.0 or FRAMES_PER_WALK <= 0:
		return 0
	var t := fmod(anim_player.current_animation_position, a.length)
	var frac := t / a.length                      # 0..1
	var base := int(frac * float(FRAMES_PER_WALK)) % FRAMES_PER_WALK
	return base
