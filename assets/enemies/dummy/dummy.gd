extends Enemy
class_name TrainingDummy

## Trainings-Dummy: steckt fest im Boden, kann geschlagen werden
## (Hit-Flash, Wackeln, VFX, SFX), stirbt aber nie.
##
## Spritesheet: 64x320px, 64x64 pro Frame (HFRAMES=1, VFRAMES=5)
## Frame 0 = Idle, Frame 1+2 = Hit, Rest = Platzhalter.

# === FRAME DEFINITIONS ===
const FRAME_IDLE: int = 0
const HIT_FRAME_LIST: Array[int] = [1, 2]

# === ANIMATION ===
@export_group("Dummy Animation")
@export var HIT_FPS: float = 8.0
@export var hit_anim_duration: float = 0.35

# === WOBBLE ===
@export_group("Wobble")
@export var wobble_strength: float = 0.12      ## maximaler Ausschlag (units)
@export var wobble_frequency: float = 22.0     ## Schwingungen pro Sekunde
@export var wobble_damping: float = 9.0        ## wie schnell es ausklingt
@export var wobble_lean: float = 0.18          ## seitliches Kippen (radians, Z-Rotation)

# === VISUAL VARIANT ===
@export_group("Visual Variant")
@export var sprite_texture_override: Texture2D
@export var sprite_modulate_override: Color = Color.WHITE

# === STATE ===
var _is_hit: bool = false
var _hit_anim_time: float = 0.0

# Wobble
var _wobble_time: float = 0.0
var _wobble_active: bool = false
var _wobble_dir: float = 1.0                   ## -1 = links, +1 = rechts (Bildschirm-X)
var _sprite_base_pos: Vector3 = Vector3.ZERO
var _sprite_base_rot: Vector3 = Vector3.ZERO


# === ENEMY OVERRIDES ===

func _on_ready_after_terrain() -> void:
	_apply_visual_variant()
	_last_position_check = global_position

	# Body fixieren: Dummy steckt im Boden, keine Gravitation/Bewegung
	set_physics_process(true)

	if sprite:
		_sprite_base_pos = sprite.position
		_sprite_base_rot = sprite.rotation

	_show_idle()


func _apply_visual_variant() -> void:
	if sprite == null:
		return
	if sprite_texture_override != null:
		sprite.texture = sprite_texture_override
	sprite.modulate = sprite_modulate_override


## Dummy bewegt sich NIE — Body bleibt fixiert.
func _process_ai(_delta: float) -> void:
	velocity = Vector3.ZERO

	if _is_hit:
		_animate_hit(_delta)
	else:
		_show_idle()


## UNSTERBLICH: HP wird nie reduziert. Wackeln + Effekte statt Knockback.
func take_damage(amount: int, from_position: Vector3, skip_hitstop: bool = false) -> void:
	if _is_dead or _is_invincible:
		return

	if _is_confused:
		_end_confusion()

	# HP NICHT reduzieren.

	_anim_time = 0.0
	_hit_anim_time = 0.0
	_is_hit = true

	_is_invincible = true
	_invincibility_timer = invincibility_duration

	# Wackelrichtung aus Treffer ableiten (Bildschirm-horizontal)
	_trigger_wobble(from_position)

	_play_sound(hurt_sound, hurt_pitch_variation)

	if not skip_hitstop and GameEffects:
		GameEffects.hit_effect()

	_on_damage_received(amount, from_position)


func _on_damage_received(_amount: int, _from_position: Vector3) -> void:
	_spawn_hit_vfx()


# === WOBBLE ===

func _trigger_wobble(from_position: Vector3) -> void:
	_wobble_active = true
	_wobble_time = 0.0

	# Richtung: von wo kam der Schlag? -> Dummy kippt in Gegenrichtung
	var camera := get_viewport().get_camera_3d()
	if camera:
		var hit_dir := (global_position - from_position)
		# Projektion auf Kamera-rechts-Achse -> Bildschirm-horizontal
		var screen_x := camera.global_transform.basis.x.dot(hit_dir)
		_wobble_dir = signf(screen_x) if absf(screen_x) > 0.001 else 1.0
	else:
		_wobble_dir = 1.0


func _process(delta: float) -> void:
	super(delta)  # WICHTIG: Basisklasse-Process (Freeze, HP-Timer, Confusion) erhalten
	_update_wobble(delta)


func _update_wobble(delta: float) -> void:
	if sprite == null:
		return

	if not _wobble_active:
		return

	_wobble_time += delta

	var envelope := exp(-wobble_damping * _wobble_time)
	var swing := sin(_wobble_time * wobble_frequency * TAU) * envelope

	# Positions-Offset (Bildschirm-horizontal) + Kippen
	sprite.position = _sprite_base_pos + Vector3(
		swing * wobble_strength * _wobble_dir,
		0.0,
		0.0
	)
	sprite.rotation = _sprite_base_rot + Vector3(
		0.0,
		0.0,
		-swing * wobble_lean * _wobble_dir
	)

	# Ausklingen beenden, wenn Schwingung vernachlässigbar
	if envelope < 0.01:
		_wobble_active = false
		sprite.position = _sprite_base_pos
		sprite.rotation = _sprite_base_rot


# === ANIMATION ===

func _show_idle() -> void:
	if sprite == null:
		return
	sprite.frame = FRAME_IDLE
	sprite.flip_h = false
	sprite.modulate = sprite_modulate_override


func _animate_hit(delta: float) -> void:
	if sprite == null:
		return

	_hit_anim_time += delta
	_anim_time += delta

	var frame_idx: int = int(_hit_anim_time * HIT_FPS) % HIT_FRAME_LIST.size()
	sprite.frame = HIT_FRAME_LIST[frame_idx]
	sprite.flip_h = false

	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else sprite_modulate_override

	if _hit_anim_time >= hit_anim_duration:
		_is_hit = false
		_show_idle()


# === HIT VFX ===

func _spawn_hit_vfx() -> void:
	if death_vfx_scene == null:
		return

	var vfx := death_vfx_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = global_position + death_vfx_offset
	vfx.scale = Vector3.ONE * death_vfx_scale

	for child in vfx.get_children():
		if child is GPUParticles3D:
			child.emitting = true

	get_tree().create_timer(death_vfx_lifetime).timeout.connect(vfx.queue_free)
