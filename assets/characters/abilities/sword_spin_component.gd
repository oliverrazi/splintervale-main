extends Node
class_name SwordSpinComponent

## Sword Spin - Kombination aus Dodge + Schwert.
## Aktivierung: Während eines aktiven Dodges (oder dessen Fade-Outs) Schwert-Taste drücken.
## Verhalten: Spieler bewegt sich kontrollierbar in Dodge-Richtung weiter, dreht sich
## mit dem Schwert und schädigt Enemies in einem kleinen Radius.
## Endet wenn RP auf 0 oder Sicherheits-Timeout erreicht. Danach 2s RP-Regen-Sperre.

signal spin_started
signal spin_ended

# === REFERENCES ===
@export var player_path: NodePath = ".."
@export var sprite_path: NodePath = "../charactersprite"
@export var dodge_component_path: NodePath = "../DodgeComponent"
@export var sword_component_path: NodePath = "../SwordComponent"

# === ACTIVATION ===
@export_group("Activation")
@export var min_resonance_to_start: int = 5
@export var resonance_drain_per_second: float = 20.0
@export var regen_lockout_after_spin: float = 2.0

# === MOVEMENT ===
@export_group("Movement")
## Anteil vom Dodge-Speed (0.5 = halb so schnell)
@export var movement_speed_factor: float = 0.5
## Wie schnell der Spieler die Richtung ändern kann (höher = agiler)
@export var input_acceleration: float = 6.0

# === DAMAGE ===
@export_group("Damage")
@export var damage_multiplier: float = 1.3
@export var hit_radius: float = 0.5
@export var hit_height_offset: float = 0.3
@export var per_enemy_hit_cooldown: float = 0.4

# === SAFETY ===
@export_group("Safety")
@export var max_duration: float = 10.0

# === FRAMES ===
@export_group("Frames")
@export var SPIN_FPS: float = 12.0
## 5 unique Frames. 8 Richtungen werden durch Flip auf diese gemappt:
## DOWN, UP, SIDE (für LEFT/RIGHT), DOWN_DIAG (für DOWN_LEFT/DOWN_RIGHT),
## UP_DIAG (für UP_LEFT/UP_RIGHT)
@export var SPIN_FRAME_DOWN: int = 28
@export var SPIN_FRAME_DOWN_DIAG: int = 73  # für DOWN_LEFT (unflipped) und DOWN_RIGHT (flipped)
@export var SPIN_FRAME_SIDE: int = 46       # für LEFT (unflipped) und RIGHT (flipped)
@export var SPIN_FRAME_UP_DIAG: int = 82    # für UP_LEFT (unflipped) und UP_RIGHT (flipped)
@export var SPIN_FRAME_UP: int = 37


# === VFX ===
@export_group("VFX - Spin Slash")
## Spin-Slash-Szene mit full-cone Mesh (Kopie von slashVFX.tscn mit ausgetauschtem Mesh)
@export var slash_scene: PackedScene
@export var slash_y_offset: float = 0.15
## Zeit zwischen zwei Spawns. Animation läuft 0.5s, mit ~0.2s ergibt sich
## sauberer Dauer-Wirbel. Niedriger = dichter, höher = pulsiger.
@export var slash_spawn_interval: float = 0.35
## Alterniert die Y-Rotation um 180° zwischen Spawns für zusätzliche Variation
@export var slash_alternate_rotation: bool = false

@export_group("Afterimage")
@export var afterimage_enabled: bool = true
@export var afterimage_interval: float = 0.06
@export var afterimage_fade_time: float = 0.32
@export var afterimage_color: Color = Color(0.55, 0.85, 1.0, 0.85)

@export_group("Spin Impact VFX")
@export var spin_impact_scene: PackedScene
@export var spin_impact_scale: float = 0.5
@export var spin_impact_delay: float = 0.0
@export var spin_impact_lifetime: float = 0.35
@export var spin_impact_y_offset: float = 0.3

# === SOUND ===
@export_group("Sound")
@export var swoosh_sounds: Array[AudioStream] = []
@export var swoosh_interval: float = 0.18
@export var swoosh_volume_db: float = -8.0
@export var swoosh_pitch_variation: float = 0.12

# === STATE ===
var _is_spinning: bool = false
var _spin_time: float = 0.0
var _slash_timer: float = 0.0
var _swoosh_timer: float = 0.0
var _spin_angle: float = 0.0
var _movement_dir: Vector3 = Vector3.ZERO
var _hit_cooldowns: Dictionary = {}  # instance_id → time_until_next_hit
var _slash_spawn_timer: float = 0.0
var _slash_alternate_flip: bool = false
var _afterimage_timer: float = 0.0

var _has_registered_hit: bool = false
var _projected_combo: int = 0
var _projected_multiplier: float = 1.0

const SYNERGY_ID: String = "sword_spin"

# === CACHED ===
var _player: CharacterBody3D = null
var _sprite: LayeredPixelSprite3D = null
var _dodge: Node = null
var _sword: Node = null

@export var synergy_manager_path: NodePath = "../SynergyManager"
var _synergy_manager: SynergyManager = null
var _current_damage_multiplier: float = 1.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_sprite = get_node_or_null(sprite_path) as LayeredPixelSprite3D
	_dodge = get_node_or_null(dodge_component_path)
	_sword = get_node_or_null(sword_component_path)
	
	_synergy_manager = get_node_or_null(synergy_manager_path) as SynergyManager
	
	if _player == null:
		push_error("SwordSpinComponent: Player not found")
	if _sprite == null:
		push_error("SwordSpinComponent: LayeredPixelSprite3D not found")


func _physics_process(delta: float) -> void:
	if _is_spinning:
		_process_spin(delta)
	
	# Hit-Cooldowns immer ticken (auch außerhalb des Spins für Sauberkeit)
	if not _hit_cooldowns.is_empty():
		var to_remove: Array = []
		for eid in _hit_cooldowns.keys():
			_hit_cooldowns[eid] -= delta
			if _hit_cooldowns[eid] <= 0.0:
				to_remove.append(eid)
		for eid in to_remove:
			_hit_cooldowns.erase(eid)


# ============================================
# PUBLIC API
# ============================================

func is_spinning() -> bool:
	return _is_spinning


## Versucht den Spin zu starten. Erfolgreich nur während eines aktiven Dodges
## und mit ausreichend Resonanz.
func try_start_spin() -> bool:
	if _is_spinning:
		return false
	if _dodge == null or not _dodge.is_dodging():
		return false
	if not _has_enough_resonance():
		return false
	
	# Synergy-Manager: Heat + History updaten, Multiplier merken
	if _synergy_manager != null:
		var result := _synergy_manager.register_synergy_use(SYNERGY_ID)
		if not result.allowed:
			return false
		_current_damage_multiplier = result.damage_multiplier
		_projected_combo = result.combo_count
		_projected_multiplier = result.damage_multiplier
	else:
		_current_damage_multiplier = 1.0
		_projected_combo = 0
		_projected_multiplier = 1.0
	
	_has_registered_hit = false
	_start_spin()
	return true


# ============================================
# SPIN LIFECYCLE
# ============================================

func _start_spin() -> void:
	_is_spinning = true
	_spin_time = 0.0
	_slash_timer = 0.0
	_swoosh_timer = 0.0
	_spin_angle = 0.0
	_hit_cooldowns.clear()
	
	# Dodge sauber beenden, ohne die Resonanz erneut zu konsumieren.
	# Wir übernehmen die Bewegungsrichtung vom Dodge.
	if _dodge != null and "_dodge_direction" in _dodge:
		_movement_dir = _dodge._dodge_direction
	else:
		_movement_dir = Vector3.ZERO
	
	# Aktuelle Schwert-Attacke abbrechen, falls Dodge aus der gepuffert wurde
	if _sword != null and _sword.has_method("cancel"):
		_sword.cancel()
	
	# Dodge übernimmt sich selbst nicht mehr — wir sagen ihm: vorbei
	if _dodge != null and _dodge.has_method("force_end_for_spin"):
		_dodge.force_end_for_spin()
	
	_slash_spawn_timer = 0.0
	_slash_alternate_flip = false
	_spawn_slash()  # erster sofort
	_play_swoosh()
	
	spin_started.emit()


func _process_spin(delta: float) -> void:
	
	if _player != null and "_is_knocked_back" in _player and _player._is_knocked_back:
		_end_spin_interrupted()
		return
	
	_spin_time += delta
	
	# ─── RP draining ───
	var drain: float = resonance_drain_per_second * delta
	if not _drain_resonance(drain):
		_end_spin()
		return
	
	# Sicherheits-Timeout
	if _spin_time >= max_duration:
		_end_spin()
		return
	
	# ─── Movement ───
	var input_dir: Vector3 = _get_input_world_dir()
	if input_dir != Vector3.ZERO:
		# Spieler steuert um → Bewegungsrichtung mit niedriger Acceleration anpassen
		_movement_dir = _movement_dir.lerp(input_dir, input_acceleration * delta).normalized()
	# Wenn kein Input: behalte aktuelle Richtung
	
	var spin_speed: float = _get_dodge_speed() * movement_speed_factor
	_player.velocity.x = _movement_dir.x * spin_speed
	_player.velocity.z = _movement_dir.z * spin_speed
	
	# ─── Sprite Frame (rotiert durch 8 Richtungen) ───
	_update_spin_frame()
	
	# ─── VFX-Timing ───
	# ─── Slash-Loop: alle slash_spawn_interval einen neuen full-cone Slash ───
	_slash_spawn_timer += delta
	if _slash_spawn_timer >= slash_spawn_interval:
		_slash_spawn_timer -= slash_spawn_interval
		_spawn_slash()
	
	# ─── Afterimages ───
	if afterimage_enabled:
		_afterimage_timer += delta
		if _afterimage_timer >= afterimage_interval:
			_afterimage_timer = 0.0
			_spawn_afterimage()
	
	# ─── Sound ───
	_swoosh_timer += delta
	if _swoosh_timer >= swoosh_interval:
		_swoosh_timer = 0.0
		_play_swoosh()
	
	# ─── Damage ───
	_damage_enemies_in_radius()


func _end_spin() -> void:
	_is_spinning = false
	_spin_time = 0.0
	
	# RP-Regen-Sperre verlängern
	if GameManager != null and GameManager.player_data != null:
		var pd: PlayerData = GameManager.player_data
		if "_resonance_regen_timer" in pd:
			pd._resonance_regen_timer = regen_lockout_after_spin
	
	# Velocity sofort weichknicken — kein abruptes Stehen, aber auch keine
	# Restbewegung in den nächsten Frame schleppen
	if _player:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
	
	# Idle-Frame zurücksetzen, damit der Player nicht im letzten Spin-Frame hängt
	if _player and _player.has_method("_show_idle"):
		_player._show_idle()
	
	spin_ended.emit()

func _end_spin_interrupted() -> void:
	# Variante von _end_spin: Spieler wurde getroffen → Spin sofort beenden,
	# RP nicht weiter verbrauchen, aber Regen-Lockout trotzdem setzen,
	# damit der Spin nicht direkt erneut gespammt werden kann.
	_is_spinning = false
	_spin_time = 0.0
	
	if GameManager != null and GameManager.player_data != null:
		var pd: PlayerData = GameManager.player_data
		if "_resonance_regen_timer" in pd:
			pd._resonance_regen_timer = regen_lockout_after_spin
	
	# Velocity NICHT auf 0 setzen — der Knockback aus take_damage soll wirken
	# Idle-Frame auch nicht setzen — der Player wird gleich Hurt-Frame zeigen
	
	spin_ended.emit()

# ============================================
# RESONANCE
# ============================================

func _has_enough_resonance() -> bool:
	if GameManager == null or GameManager.player_data == null:
		return false
	return GameManager.player_data.current_resonance >= float(min_resonance_to_start)


func _drain_resonance(amount: float) -> bool:
	if GameManager == null or GameManager.player_data == null:
		return true
	
	var pd: PlayerData = GameManager.player_data
	if pd.current_resonance <= 0.0:
		return false
	
	pd.current_resonance = max(0.0, pd.current_resonance - amount)
	pd.resonance_changed.emit(int(pd.current_resonance), pd.max_resonance)
	
	return pd.current_resonance > 0.0


# ============================================
# MOVEMENT INPUT
# ============================================

func _get_input_world_dir() -> Vector3:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	input_dir = input_dir.normalized()
	
	var spring_arm: Node3D = _player.get_node_or_null("SpringArm3D") as Node3D
	if spring_arm == null:
		return Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	var yaw: float = spring_arm.rotation.y
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return (right * input_dir.x + forward * input_dir.y).normalized()


func _get_dodge_speed() -> float:
	if _dodge != null and "dodge_speed" in _dodge:
		return _dodge.dodge_speed
	return 120.0  # Fallback


# ============================================
# SPRITE FRAME ROTATION
# ============================================

func _update_spin_frame() -> void:
	if _sprite == null:
		return
	
	# 8-Schritt-Sequenz, die im Kreis dreht.
	# Jeder Eintrag: {frame, flip_h}
	var sequence: Array[Dictionary] = [
		{frame = SPIN_FRAME_DOWN,      flip = false},  # DOWN
		{frame = SPIN_FRAME_DOWN_DIAG, flip = true},   # DOWN_RIGHT (gespiegelt von DOWN_LEFT)
		{frame = SPIN_FRAME_SIDE,      flip = true},   # RIGHT (gespiegelt von LEFT/SIDE)
		{frame = SPIN_FRAME_UP_DIAG,   flip = false},   # UP_RIGHT (gespiegelt von UP_LEFT)
		{frame = SPIN_FRAME_UP,        flip = false},  # UP
		{frame = SPIN_FRAME_UP_DIAG,   flip = true},  # UP_LEFT
		{frame = SPIN_FRAME_SIDE,      flip = false},  # LEFT
		{frame = SPIN_FRAME_DOWN_DIAG, flip = false},  # DOWN_LEFT
	]
	
	var idx: int = int(_spin_time * SPIN_FPS) % sequence.size()
	var entry: Dictionary = sequence[idx]
	
	_sprite.frame = entry.frame
	_sprite.flip_h = entry.flip


# ============================================
# DAMAGE
# ============================================

func _damage_enemies_in_radius() -> void:
	var center: Vector3 = _player.global_position + Vector3(0, hit_height_offset, 0)
	var radius_sq: float = hit_radius * hit_radius
	
	# (Block, der vorher hier oben falsch stand — ist gelöscht)
	
	for group in ["enemies", "enemy"]:
		for node in _player.get_tree().get_nodes_in_group(group):
			if not (node is Node3D):
				continue
			if not is_instance_valid(node):
				continue
			
			var enemy_pos: Vector3 = (node as Node3D).global_position + Vector3(0, hit_height_offset, 0)
			if enemy_pos.distance_squared_to(center) > radius_sq:
				continue
			
			var eid: int = node.get_instance_id()
			if _hit_cooldowns.has(eid):
				continue
			
			# Tote ignorieren
			if "_is_dead" in node and node._is_dead:
				continue
			if not node.has_method("take_damage"):
				continue
			
			# Synergie beim ersten Hit überhaupt registrieren — hier unten,
			# nach allen Validierungen und nur wenn wirklich ein Enemy getroffen wird
			if _synergy_manager != null:
				if not _has_registered_hit:
					_synergy_manager.register_synergy_hit(_projected_combo, _projected_multiplier)
					_has_registered_hit = true
				else:
					_synergy_manager.refresh_combo_timer()
			
			var damage: int = _calculate_damage()
			# skip_hitstop = true, damit Combat flüssig bleibt
			node.take_damage(damage, _player.global_position, true)
			_hit_cooldowns[eid] = per_enemy_hit_cooldown
			
			var impact_pos: Vector3 = (node as Node3D).global_position + Vector3(0, spin_impact_y_offset, 0)
			CombatVFXUtils.spawn_impact(self, spin_impact_scene, impact_pos, spin_impact_scale, spin_impact_delay, spin_impact_lifetime)

func _calculate_damage() -> int:
	var sword_base: int = 5
	if _sword != null and "attack_damage" in _sword:
		sword_base = _sword.attack_damage
	
	var normal_damage: int = sword_base
	if GameManager != null and GameManager.player_data != null:
		normal_damage = GameManager.player_data.get_attack_damage(sword_base)
	
	var with_combo: float = float(normal_damage) * damage_multiplier
	with_combo *= _current_damage_multiplier
	return int(round(with_combo))


# ============================================
# VFX
# ============================================

func _play_swoosh() -> void:
	if swoosh_sounds.is_empty():
		return	
	AudioPool.play_3d(
		swoosh_sounds.pick_random(),
		_player.global_position,
		swoosh_volume_db,
		randf_range(1.0 - swoosh_pitch_variation, 1.0 + swoosh_pitch_variation)
	)



# ============================================
# SPIN SLASH SPAWN
# ============================================

func _spawn_slash() -> void:
	if slash_scene == null or _player == null:
		return
	
	var slash := slash_scene.instantiate() as Node3D
	_player.add_child(slash)
	slash.position = Vector3(0, slash_y_offset, 0)
	
	if slash_alternate_rotation and _slash_alternate_flip:
		slash.rotation_degrees.y = 180.0
	_slash_alternate_flip = not _slash_alternate_flip
	
	var hit_area: Area3D = slash.get_node_or_null("Node3D/HitArea") as Area3D
	if hit_area:
		hit_area.monitoring = false
		hit_area.monitorable = false
	
	# Material-Override aus der Szene wird respektiert — keine Color-Overrides hier.
	# Falls du Farben pro Spawn ändern willst, mach das in der spin_slashVFX.tscn
	# direkt am SurfaceMaterialOverride.
	
	# Animation abspielen — selbstaufräumend, ohne externen Timer
	var anim: AnimationPlayer = slash.get_node_or_null("Node3D/AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("slash"):
		anim.play("slash")
		# Wenn die Animation fertig ist, Slash entfernen — synchron zur tatsächlichen
		# Anim-Länge, ohne dass ein Timer das früher abschneidet.
		anim.animation_finished.connect(func(_anim_name: StringName):
			if is_instance_valid(slash):
				slash.queue_free()
		, CONNECT_ONE_SHOT)
	else:
		# Fallback falls keine Animation gefunden — einfacher Timer
		_player.get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(slash):
				slash.queue_free()
		)

# ============================================
# AFTERIMAGE
# ============================================

func _spawn_afterimage() -> void:
	if _sprite == null:
		return
	if not _sprite.has_method("get_all_layer_keys"):
		return
	
	for layer_key in _sprite.get_all_layer_keys():
		var layer_sprite: SmoothPixelSprite3D = _sprite.get_layer(layer_key)
		if layer_sprite == null or not layer_sprite.visible:
			continue
		if layer_sprite.texture == null:
			continue
		
		var ghost := Sprite3D.new()
		ghost.texture = layer_sprite.texture
		ghost.hframes = layer_sprite.hframes
		ghost.vframes = layer_sprite.vframes
		ghost.frame = layer_sprite.frame
		ghost.flip_h = layer_sprite.flip_h
		ghost.pixel_size = layer_sprite.pixel_size
		ghost.centered = true
		ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ghost.render_priority = -1
		ghost.modulate = afterimage_color
		
		_player.get_tree().current_scene.add_child(ghost)
		ghost.global_transform = layer_sprite.global_transform
		
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time).set_ease(Tween.EASE_IN)
		tween.tween_property(ghost, "scale", ghost.scale * 0.85, afterimage_fade_time).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(ghost.queue_free)
