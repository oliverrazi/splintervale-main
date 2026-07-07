extends Enemy
class_name Fish

## Fisch-Gegner: lauert im Wasser, springt im Bogen auf den Player, hält danach
## bedächtig Abstand und schnappt im richtigen Moment zu. Weicht Schwertschlägen
## mit einem kleinen Rückwärts-Hop aus (wie die Skelette in Zelda ALttP).
##
## Kampf-Loop:
##   LURK         – lauert im Wasser (floatet sanft), wartet bis Player nah → LEAP
##   LEAP         – kinematischer Parabel-Sprung auf den Player; trifft beim Aufkommen.
##                  NICHT unterbrechbar: Treffer macht Schaden, stunnt aber nicht.
##   LAND         – kurzer Recovery-Tick → OBSERVE
##   OBSERVE      – Thinking-Phase: hält bedächtig Abstand (geht im Normaltempo ran/zurück),
##                  beobachtet ruhig. Holt der Player zum Schlag aus und der Fisch ist nah,
##                  macht er einen kleinen Parabel-Hop zurück (ALttP-Skelett-Ausweichen).
##   CIRCLE       – kreiselt seitlich um den Player; weicht ebenfalls aus.
##   APPROACH     – geht gezielt auf Snap-Reichweite heran, um dann zu schnappen.
##   SNAP_WINDUP  – Ausholen (2 Frames, Telegraph). COMMITTED: Treffer → Stun (Combo-Fenster!).
##   SNAP         – Zuschnappen, kurzes Vorpreschen; trifft bei Nähe. COMMITTED.
##   SNAP_RECOVERY– kurze Erholung → OBSERVE
##   HOP          – kleiner reaktiver Ausweich-Sprung zurück (Parabel)
##   STUN         – kurz betäubt nach Treffer im committed-State
##   DEAD         – 3 Death-Frames; VFX/Ash/Rewards via Basisklasse
##
## Kernidee: Bedächtiger, vorsichtiger Gegner. Er tänzelt um den Player, weicht
## Schlägen gezielt aus und schnappt im richtigen Augenblick zu. Der Skill liegt
## darin, seine Ausweich-Reaktion zu überlisten und das Windup-Fenster zu treffen.


# === SPRITE GRID ===
@export_group("Sprite Grid")
@export var fish_hframes: int = 10
@export var fish_vframes: int = 4

# === MOVEMENT ===
@export_group("Movement")
@export var WALK_SPEED: float = 1.4              ## bedächtiges Geh-Tempo (ran/zurück im Observe)
@export var approach_speed: float = 1.8          ## Tempo beim gezielten Annähern für den Snap

# === LEAP ===
@export_group("Leap")
@export var LEAP_DURATION: float = 1.0           ## Dauer des Bogensprungs
@export var LEAP_ARC_HEIGHT: float = 1.1         ## Scheitelhöhe des Sprungbogens
@export var leap_max_range: float = 6.0          ## maximale Sprungdistanz
@export var leap_min_range: float = 2.0          ## minimale Distanz, ab der ein Leap sinnvoll ist
@export var leap_target_shorten: float = 0.4     ## Verkürzung des Ziels (landet knapp vor dem Player)
@export var leap_hit_from_t: float = 0.55        ## ab diesem Bogen-Fortschritt (Landephase) ist die AttackArea aktiv
@export var land_recovery: float = 0.5           ## Erholung nach der Landung

# === OBSERVE (Spacing, bedächtig) ===
@export_group("Observe")
@export var preferred_distance: float = 1.4           ## Wunschabstand – nah genug für Snap
@export var preferred_distance_tolerance: float = 0.4 ## Toleranzband um den Wunschabstand
@export var observe_time_min: float = 0.8             ## min. Beobachtungsdauer pro Zyklus
@export var observe_time_max: float = 1.6             ## max. Beobachtungsdauer pro Zyklus

# === CIRCLE ===
@export_group("Circle")
@export var circle_speed: float = 1.1                 ## Seitwärtstempo beim Kreiseln
@export var circle_time_min: float = 0.5              ## min. Kreisel-Dauer
@export var circle_time_max: float = 1.0              ## max. Kreisel-Dauer

# === DECISION (Verhaltens-Wahrscheinlichkeiten nach Observe) ===
@export_group("Decision")
@export var snap_chance: float = 0.5             ## Chance zu snappen (wenn nah genug)
@export var circle_chance: float = 0.3           ## Chance zu kreiseln
@export var leap_chance: float = 0.25            ## Chance zu springen (wenn weit genug)
## Rest = weiter beobachten

# === REACTIVE HOP (Ausweichen vor Schwertschlag) ===
@export_group("Reactive Hop")
@export var hop_trigger_range: float = 1.6       ## nur ausweichen, wenn Player in dieser Schlagreichweite
@export var hop_distance: float = 1.3            ## Weite des Ausweich-Hops
@export var hop_duration: float = 0.5            ## Dauer des Hops
@export var hop_arc_height: float = 0.4          ## Scheitelhöhe des kleinen Hop-Bogens
@export var hop_cooldown: float = 0.4            ## Pause, bevor erneut gehoppt werden kann

# === SNAP ===
@export_group("Snap")
@export var snap_range: float = 1.9              ## Distanz, ab der ein Snap startet
@export var snap_windup_time: float = 0.8        ## Aushol-Dauer (Telegraph, 2 Frames)
@export var snap_active_time: float = 0.2        ## aktives Schnapp-Fenster
@export var snap_recovery_time: float = 0.8      ## Erholung nach Snap
@export var snap_advance_speed: float = 6.0      ## Vorwärts-Schub im Snap (überbrückt Restdistanz)
@export var snap_hit_radius: float = 0.85        ## Vorpresch-Stoppdistanz im Snap (Treffer läuft über echte Kollision)

# === COMBAT ===
@export_group("Combat")
@export var damage: int = 5
@export var detect_range: float = 5.5            ## Distanz, ab der der Fisch aus LURK reagiert

# === STUN ===
@export_group("Stun")
@export var stun_duration: float = 0.6

# === ANIMATION ===
@export_group("Animation")
@export var WALK_FPS: float = 8.0

# === LURK FLOATING ===
@export_group("Lurk Floating")
@export var lurk_bob_amount: float = 0.04
@export var lurk_bob_speed: float = 2.0
@export var lurk_sway_amount: float = 0.03
@export var lurk_sway_speed: float = 1.3

# === VISUAL VARIANT ===
@export_group("Visual Variant")
@export var sprite_texture_override: Texture2D
@export var sprite_modulate_override: Color = Color.WHITE

# === WATER RECOVERY ===
@export_group("Water Recovery")
@export var water_submerge_depth: float = 0.35
@export var water_sink_speed: float = 1.5
@export var water_wait_time: float = 1.2
@export var water_settle_threshold: float = 0.05

# === WATER FX (SFX + VFX beim Eintauchen und Auftauchen/Absprung) ===
@export_group("Water FX")
@export var water_enter_sfx: AudioStream       ## Sound beim Eintauchen ins Wasser
@export var water_leap_sfx: AudioStream        ## Sound beim Absprung aus dem Wasser
@export var water_enter_vfx: PackedScene       ## VFX-Szene beim Eintauchen (z.B. Splash)
@export var water_leap_vfx: PackedScene        ## VFX-Szene beim Absprung aus dem Wasser
@export var water_fx_volume_db: float = 0.0    ## Lautstärke-Offset für die Wasser-Sounds
@export var water_fx_y_offset: float = 0.0     ## vertikaler Versatz für die VFX-Instanz


# === FRAME DEFINITIONS ===
# Sheet 10×4. 8 Richtungen → 5 Sprites: RIGHT/LEFT (flip),
# DOWN_RIGHT/DOWN_LEFT (flip), UP_RIGHT/UP_LEFT (flip); DOWN/UP eigenständig.

const LURK_FRAME: int = 0

const LEAP_RIGHT: int = 21
const LEAP_DOWN_RIGHT: int = 21
const LEAP_DOWN: int = 21
const LEAP_UP_RIGHT: int = 21
const LEAP_UP: int = 21

const IDLE_RIGHT: int = 1
const IDLE_DOWN_RIGHT: int = 2
const IDLE_DOWN: int = 3
const IDLE_UP_RIGHT: int = 4
const IDLE_UP: int = 5

const LAND_RIGHT: int = 1
const LAND_DOWN_RIGHT: int = 2
const LAND_DOWN: int = 3
const LAND_UP_RIGHT: int = 4
const LAND_UP: int = 5

const WALK_RIGHT: Array[int] = [6, 7, 8, 7]
const WALK_DOWN_RIGHT: Array[int] = [9, 10, 11, 10]
const WALK_DOWN: Array[int] = [12, 3, 14, 13]
const WALK_UP_RIGHT: Array[int] = [15, 4, 16, 4]
const WALK_UP: Array[int] = [17, 5, 19, 18]

const SNAP_WINDUP_RIGHT: Array[int] = [22, 23]
const SNAP_WINDUP_DOWN_RIGHT: Array[int] = [25, 26]
const SNAP_WINDUP_DOWN: Array[int] = [28, 29]
const SNAP_WINDUP_UP_RIGHT: Array[int] = [31, 32]
const SNAP_WINDUP_UP: Array[int] = [34, 35]

const SNAP_RIGHT: int = 24
const SNAP_DOWN_RIGHT: int = 27
const SNAP_DOWN: int = 30
const SNAP_UP_RIGHT: int = 33
const SNAP_UP: int = 36

const HURT_RIGHT: int = 21
const HURT_DOWN_RIGHT: int = 21
const HURT_DOWN: int = 21
const HURT_UP_RIGHT: int = 21
const HURT_UP: int = 21

const DEATH_FRAME_LIST: Array[int] = [21, 20, 37]
const DROWN_FRAME: int = 0


# === STATE MACHINE ===
enum State {
	LURK,
	LEAP, LAND,
	OBSERVE, CIRCLE, APPROACH,
	SNAP_WINDUP, SNAP, SNAP_RECOVERY,
	HOP, STUN,
	DEAD, CONFUSED,
}
var _state: State = State.LURK
var _state_timer: float = 0.0

## States, in denen ein Player-Treffer den Fisch STUNNT (Combo-Fenster).
## LEAP/HOP bewusst NICHT dabei – diese Sprünge laufen sauber zu Ende.
const STUNNABLE_STATES := [State.SNAP_WINDUP, State.SNAP, State.LAND]
## States, in denen der Fisch auf einen startenden Schwertschlag mit einem Hop ausweicht.
const HOP_REACTIVE_STATES := [State.OBSERVE, State.CIRCLE, State.APPROACH]

# === DIRECTION ===
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }
var _facing_dir: int = DirMode.DOWN

# === ATTACK AREA (zuverlässige Treffer via Area3D, kein Frame-Tunneling) ===
@onready var attack_area: Area3D = get_node_or_null("AttackArea")
var _attack_active: bool = false          ## AttackArea-Treffer nur wenn true (während Leap/Snap)
var _attack_hit_this_action: bool = false ## verhindert Doppeltreffer pro Aktion

# === LEAP STATE ===
var _leap_start: Vector3 = Vector3.ZERO
var _leap_target: Vector3 = Vector3.ZERO
var _leap_t: float = 0.0
var _leap_has_hit: bool = false

# === HOP STATE (reaktives Ausweichen) ===
var _hop_start: Vector3 = Vector3.ZERO
var _hop_target: Vector3 = Vector3.ZERO
var _hop_t: float = 0.0
var _hop_cooldown_timer: float = 0.0
var _hop_return_state: int = State.OBSERVE  ## wohin nach dem Hop zurück

# === SNAP STATE ===
var _snap_has_hit: bool = false
var _snap_dir: Vector3 = Vector3.ZERO

# === CIRCLE STATE ===
var _circle_dir: int = 1

# === STUN STATE ===
var _stun_timer: float = 0.0

# === LURK FLOATING ===
var _lurk_anchor: Vector3 = Vector3.ZERO
var _lurk_phase: float = 0.0

# === WATER RECOVERY ===
var _is_recovering: bool = false
var _recover_timer: float = 0.0
var _water_target_y: float = 0.0
enum WaterPhase { SINKING, WAITING }
var _water_phase: int = WaterPhase.SINKING

# === GROUND OFFSET ===
## Abstand Origin↔Boden, wenn der Fisch sauber steht. Lazy gemessen (siehe
## _get_ground_offset). -1 = noch nicht gemessen.
var _ground_offset: float = -1.0

# === PLAYER ATTACK DETECTION ===
var _player_was_attacking: bool = false  ## Flankenerkennung für sword.is_attacking()


# === PHYSICS OVERRIDE ===

## LEAP, HOP und LURK laufen ISOLIERT (rein kinematisch, kein move_and_slide),
## damit Sprungbögen nicht mit dem Boden kollidieren, den sie überfliegen, und
## das Wasser-Floating nicht mit der Gravity kämpft. Alle Boden-States laufen
## normal über super() (Gravity + move_and_slide).
func _physics_process(delta: float) -> void:
	if _is_dead or _is_frozen or _is_drowning:
		super(delta)
		return

	if _is_recovering:
		_tick_invincibility(delta)
		_process_water_recovery(delta)
		return

	if _state == State.LEAP:
		_tick_invincibility(delta)
		_process_leap(delta)
		return
	if _state == State.HOP:
		_tick_invincibility(delta)
		_process_hop(delta)
		return
	if _state == State.LURK:
		_tick_invincibility(delta)
		_process_lurk(delta)
		return

	# Fall ins Wasser abfangen, bevor die Basisklasse kill_instantly() ruft.
	if is_inside_tree() and get_world_3d() != null:
		if global_position.y < _spawn_position.y - fall_death_y_offset:
			_begin_water_recovery()
			return

	super(delta)


## Zählt den Invincibility-Timer der Basis herunter, wenn der Fisch in einem
## isolierten State läuft (LEAP/HOP/LURK/Water-Recovery), in dem super() NICHT
## aufgerufen wird. Ohne das würde der Timer einfrieren und _is_invincible
## dauerhaft true bleiben → alle weiteren Treffer verpuffen (Bug: "trifft, aber
## kein Schaden"). Spiegelt die i-frame-Logik der Basisklasse.
func _tick_invincibility(delta: float) -> void:
	if _is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_is_invincible = false


# === WATER RECOVERY ===

func _begin_water_recovery() -> void:
	_is_recovering = true
	_water_phase = WaterPhase.SINKING
	velocity = Vector3.ZERO
	_water_target_y = global_position.y - water_submerge_depth
	# Eintauch-FX an der Wasseroberfläche (direction +1 = eintauchen, wie beim Player).
	_play_water_fx(water_enter_sfx, water_enter_vfx, 1.0)
	_spawn_splash_vfx()
	_animate_lurk()


func _process_water_recovery(delta: float) -> void:
	velocity = Vector3.ZERO

	match _water_phase:
		WaterPhase.SINKING:
			global_position.y = move_toward(
				global_position.y, _water_target_y, water_sink_speed * delta
			)
			_animate_lurk()
			if absf(global_position.y - _water_target_y) <= water_settle_threshold:
				global_position.y = _water_target_y
				_water_phase = WaterPhase.WAITING
				_recover_timer = water_wait_time
				_lurk_anchor = global_position
				_lurk_phase = 0.0

		WaterPhase.WAITING:
			_lurk_phase += delta
			_apply_lurk_float(_water_target_y)
			_animate_lurk()
			_recover_timer -= delta
			if _recover_timer <= 0.0:
				_end_water_recovery()


func _end_water_recovery() -> void:
	_is_recovering = false
	var player := get_player()
	if player and is_instance_valid(player):
		_target = player
		# AUS DEM WASSER IMMER LEAPEN – niemals in einen Boden-State (OBSERVE/CIRCLE)
		# wechseln. Der Fisch schwebt gerade auf Schwimmhöhe über dem Seeboden; ein
		# Boden-State liefe über super() mit Gravity und ließe ihn zum Seeboden
		# absacken (auf die falsche Ebene). Der Leap trägt ihn wieder hoch zum Player.
		# Absprung-FX beim Herausschnellen aus dem Wasser (direction -1 = auftauchen).
		_play_water_fx(water_leap_sfx, water_leap_vfx, -1.0)
		_enter_state(State.LEAP)
	else:
		# Kein Player → zurück ins Lauern, aber auf der aktuellen (Schwimm-)Höhe
		# floaten statt über Gravity abzusacken. LURK läuft isoliert (kein Drop).
		_enter_state(State.LURK)


func start_drowning() -> void:
	if _is_dead or _is_recovering:
		return
	_begin_water_recovery()


## Spielt einen Wasser-Sound und spawnt optional eine VFX-Szene an der Wasser-
## oberfläche. Nutzt dieselbe WaterSplash-API wie der Player: splash.play(point,
## direction, scale). `direction` = +1 beim Eintauchen, -1 beim Herausschnellen.
## WICHTIG: Die Splash-Szene startet ihre Partikel erst in play() – ohne diesen
## Aufruf bliebe sie unsichtbar. Beide FX-Parameter sind optional (null wird ignoriert).
func _play_water_fx(sfx: AudioStream, vfx: PackedScene, direction: float = 1.0) -> void:
	var impact_point := global_position
	impact_point.y += 0.15 + water_fx_y_offset

	if sfx != null:
		_play_positional_sfx(sfx, impact_point)

	if vfx == null:
		return

	var splash := vfx.instantiate()
	get_tree().current_scene.add_child(splash)
	splash.global_position = impact_point

	if splash.has_method("play"):
		# WaterSplash-API: play(impact_point, direction, scale)
		splash.play(impact_point, direction, 1.0)
	else:
		# Fallback für Fremd-Szenen: GPUParticles direkt starten.
		for child in splash.get_children():
			if child is GPUParticles3D:
				(child as GPUParticles3D).emitting = true

	# Aufräumen nach Lebensdauer (falls die Szene sich nicht selbst freigibt).
	get_tree().create_timer(2.0).timeout.connect(splash.queue_free)


## Spielt einen Sound positional ab. Nutzt das AudioPool-Autoload, falls vorhanden
## (empfohlener Pfad im Projekt), sonst Fallback auf einen temporären Player.
func _play_positional_sfx(stream: AudioStream, at: Vector3) -> void:
	var pool := get_node_or_null("/root/AudioPool")
	if pool != null and pool.has_method("play_sound_at"):
		pool.play_sound_at(stream, at, water_fx_volume_db)
		return
	# Fallback: selbstlöschender 3D-Player.
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = water_fx_volume_db
	get_tree().current_scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


## Sanftes Wabern um eine Ankerposition – wie echtes Schwimmen im Wasser.
func _apply_lurk_float(base_y: float) -> void:
	var bob := sin(_lurk_phase * lurk_bob_speed) * lurk_bob_amount
	var sway := sin(_lurk_phase * lurk_sway_speed + 1.7) * lurk_sway_amount
	global_position.x = _lurk_anchor.x + sway
	global_position.y = base_y + bob


# === ENEMY OVERRIDES ===

func _on_ready_after_terrain() -> void:
	if sprite:
		sprite.hframes = fish_hframes
		sprite.vframes = fish_vframes
	# WICHTIG: Den Steh-Offset NICHT hier messen – zu diesem frühen Zeitpunkt ist
	# die Terrain3D-Kollision unter dem Fisch evtl. noch nicht gestreamt (Race),
	# der Raycast läge daneben → Offset 0 → Fisch steckt später im Boden.
	# Stattdessen wird der Offset LAZY beim ersten gültigen Boden-Kontakt gemessen.
	_ground_offset = -1.0  # -1 = noch nicht gemessen
	_setup_attack_area()
	_apply_visual_variant()
	_last_position_check = global_position
	_lurk_anchor = global_position
	_enter_state(State.LURK)


## Verbindet die AttackArea (Area3D + CollisionShape3D als Kind der Fisch-Szene,
## analog zum Goblin). Der Treffer läuft über body_entered → kein Frame-Tunneling
## mehr wie bei der diskreten Überlappungsabfrage. Initial deaktiviert.
func _setup_attack_area() -> void:
	if attack_area == null:
		push_warning("%s: Keine 'AttackArea' (Area3D) gefunden – Leap/Snap-Treffer via AttackArea inaktiv." % name)
		return
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	_set_attack_active(false)


## Aktiviert/deaktiviert die AttackArea. Beim Aktivieren wird das Doppeltreffer-
## Flag zurückgesetzt, sodass die neue Aktion (Leap/Snap) wieder treffen darf.
func _set_attack_active(active: bool) -> void:
	_attack_active = active
	if active:
		_attack_hit_this_action = false
	if attack_area:
		attack_area.monitoring = active


func _on_attack_area_body_entered(body: Node3D) -> void:
	if not _attack_active or _attack_hit_this_action:
		return
	if body.is_in_group("player") or body == _target:
		if body.has_method("take_damage"):
			_attack_hit_this_action = true
			_leap_has_hit = true
			_snap_has_hit = true
			body.take_damage(damage, global_position)


## Liefert den Steh-Offset (Abstand Origin↔Boden, wenn der Fisch sauber steht).
## Wird lazy gemessen, sobald ein plausibler Boden-Raycast gelingt. Bis dahin
## Fallback aus der Collider-Geometrie. Nicht an is_on_floor gekoppelt, weil das
## im isolierten LURK/Leap nicht zuverlässig aktualisiert wird.
func _get_ground_offset() -> float:
	if _ground_offset >= 0.0:
		return _ground_offset
	# Messen: Boden direkt unter dem Fisch. Wenn der Fisch gerade sauber steht
	# (was beim Sprungstart aus OBSERVE/LURK der Fall ist), ist diff der echte
	# Offset. Plausibilitätsgrenze verhindert Ausreißer bei schrägem Terrain.
	var gy := _raycast_ground_y(global_position, global_position.y + 0.5)
	if not is_nan(gy):
		var diff := global_position.y - gy
		if diff >= 0.0 and diff <= 1.0:  # plausibler Bereich für Mini-Maßstab
			_ground_offset = diff
			return _ground_offset
	# Noch keine gültige Messung → Fallback aus Collider-Geometrie.
	return _fallback_ground_offset()


## Fallback-Offset aus der Collider-Geometrie (nur wenn Live-Messung scheitert).
func _fallback_ground_offset() -> float:
	var cs := _find_own_collision_shape()
	if cs and cs.shape:
		var s := cs.shape
		if s is CapsuleShape3D:
			return (s as CapsuleShape3D).height * 0.5 - cs.position.y
		elif s is BoxShape3D:
			return (s as BoxShape3D).size.y * 0.5 - cs.position.y
		elif s is CylinderShape3D:
			return (s as CylinderShape3D).height * 0.5 - cs.position.y
		elif s is SphereShape3D:
			return (s as SphereShape3D).radius - cs.position.y
	return 0.15  # letzter Notnagel für Mini-Maßstab


func _apply_visual_variant() -> void:
	if sprite == null:
		return
	if sprite_texture_override != null:
		sprite.texture = sprite_texture_override
	sprite.modulate = sprite_modulate_override


## Treffer landen IMMER. Im committed-State stunnt der Treffer zusätzlich.
## LEAP/HOP stunnen nicht – diese Sprünge laufen sauber zu Ende.
func _on_damage_received(_amount: int, from_position: Vector3) -> void:
	var attacker := get_tree().get_first_node_in_group("player")
	if attacker:
		_target = attacker

	if _state in STUNNABLE_STATES or _state == State.STUN:
		var knockback_dir := (global_position - from_position).normalized()
		_update_facing_direction(-knockback_dir)
		_enter_state(State.STUN)
	else:
		# Nicht-stunbare States (OBSERVE/CIRCLE/LEAP/HOP/…): Der Fisch macht
		# unbeirrt weiter. Den von der Basis gesetzten Knockback hier verwerfen,
		# damit er sich nicht aufstaut und später (beim nächsten STUN) verzögert
		# als "merkwürdiger" Ruck zuschlägt.
		_knockback_velocity = Vector3.ZERO


func _on_death() -> void:
	_is_recovering = false
	_state = State.DEAD


func _get_death_frames() -> Array[int]:
	return DEATH_FRAME_LIST


func _get_drown_frame() -> int:
	return DROWN_FRAME


func _get_hurt_frame() -> Dictionary:
	return {frame = HURT_DOWN, flip = false}


# === AI DISPATCH ===

func _process_ai(delta: float) -> void:
	if is_confused():
		_animate_idle()
		return

	# Hop-Cooldown global herunterzählen.
	if _hop_cooldown_timer > 0.0:
		_hop_cooldown_timer -= delta

	match _state:
		State.LAND:
			_process_land(delta)
		State.OBSERVE:
			_process_observe(delta)
		State.CIRCLE:
			_process_circle(delta)
		State.APPROACH:
			_process_approach(delta)
		State.SNAP_WINDUP:
			_process_snap_windup(delta)
		State.SNAP:
			_process_snap(delta)
		State.SNAP_RECOVERY:
			_process_snap_recovery(delta)
		State.STUN:
			_process_stun(delta)
		State.CONFUSED:
			_animate_idle()
		# LEAP, HOP, LURK laufen isoliert in _physics_process.

	if _state == State.STUN:
		_apply_knockback(delta)


## Wendet den Knockback im STUN an. Die horizontale Velocity wird DIREKT auf den
## (abklingenden) Knockback-Wert gesetzt – NICHT additiv, sonst schaukelt sich die
## Geschwindigkeit über die Stun-Dauer auf ("beschleunigt bis zum Ende"). So klingt
## der Schub sauber ab. move_and_slide (Basis) trägt die Bewegung.
func _apply_knockback(delta: float) -> void:
	if _knockback_velocity.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector3.ZERO, knockback_strength * 3.0 * delta
	)


# === PLAYER ATTACK DETECTION ===

## Liest den aktuellen Angriffsstatus des Spielers (ohne Flankenlogik).
func _player_is_attacking() -> bool:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return false
	var sword: Variant = player.get("sword")
	if sword != null and is_instance_valid(sword) and sword.has_method("is_attacking"):
		return sword.is_attacking()
	return false


## Liest, ob der Player gerade einen Schwertangriff STARTET (Flanke false→true).
## Nutzt player.sword.is_attacking(). Gibt true zurück im Moment des Ausholens.
func _player_started_attack() -> bool:
	var attacking := _player_is_attacking()
	var just_started := attacking and not _player_was_attacking
	_player_was_attacking = attacking
	return just_started


## Prüft, ob ein reaktiver Ausweich-Hop ausgelöst werden soll, und startet ihn.
## Bedingungen: Player holt zum Schlag aus, ist in Schlagreichweite, kein Cooldown.
## Gibt true zurück, wenn ein Hop gestartet wurde (Aufrufer soll dann abbrechen).
func _try_reactive_hop(dist: float) -> bool:
	if _hop_cooldown_timer > 0.0:
		return false
	if dist > hop_trigger_range:
		return false
	if not _player_started_attack():
		return false
	_start_hop()
	return true


# === STATE MANAGEMENT ===

func _enter_state(new_state: State) -> void:
	_state = new_state
	_anim_time = 0.0

	# Sicherheit: Bei JEDEM State-Wechsel die AttackArea erst deaktivieren.
	# Die States LEAP (Landephase) und SNAP aktivieren sie danach selbst wieder.
	# So bleibt sie nie versehentlich aktiv (z.B. bei STUN/Tod mitten im Angriff).
	if new_state != State.SNAP:
		_set_attack_active(false)

	match new_state:
		State.LURK:
			velocity = Vector3.ZERO
			_lurk_anchor = global_position
			# Nur auf Bodenhöhe nachjustieren, wenn der Steh-Offset bereits gültig
			# gemessen wurde. Beim frühen Spawn (Offset noch ungemessen) bleibt die
			# Spawn-Position erhalten – der Fisch steht dort ohnehin korrekt.
			if not _is_recovering and _ground_offset >= 0.0:
				var gy := _raycast_ground_y(global_position, global_position.y + 0.5)
				if not is_nan(gy):
					_lurk_anchor.y = gy + _ground_offset
					global_position.y = _lurk_anchor.y
			_lurk_phase = 0.0
			_reset_stuck_detection()

		State.LEAP:
			_start_leap()

		State.LAND:
			_state_timer = land_recovery
			velocity = Vector3.ZERO
			_reset_stuck_detection()

		State.OBSERVE:
			_state_timer = randf_range(observe_time_min, observe_time_max)
			velocity = Vector3.ZERO
			_player_was_attacking = _player_is_attacking()
			_reset_stuck_detection()
			_face_target()

		State.CIRCLE:
			_state_timer = randf_range(circle_time_min, circle_time_max)
			_player_was_attacking = _player_is_attacking()
			_reset_stuck_detection()
			if randf() > 0.5:
				_circle_dir *= -1
			_face_target()

		State.APPROACH:
			velocity = Vector3.ZERO
			_player_was_attacking = _player_is_attacking()
			_reset_stuck_detection()
			_face_target()

		State.SNAP_WINDUP:
			_state_timer = snap_windup_time
			velocity = Vector3.ZERO
			_reset_stuck_detection()
			_face_target()

		State.SNAP:
			_state_timer = snap_active_time
			_snap_has_hit = false
			_face_target()
			_snap_dir = _dir_to_target()
			_set_attack_active(true)  # AttackArea an – trifft beim Zuschnappen

		State.SNAP_RECOVERY:
			_state_timer = snap_recovery_time
			velocity = Vector3.ZERO
			_set_attack_active(false)  # AttackArea aus
			_reset_stuck_detection()

		State.HOP:
			pass  # _start_hop() hat alles gesetzt

		State.STUN:
			_stun_timer = stun_duration
			velocity = Vector3.ZERO
			_reset_stuck_detection()

		State.CONFUSED:
			velocity = Vector3.ZERO
			_reset_stuck_detection()


# === STATE PROCESSING ===

func _process_lurk(delta: float) -> void:
	_lurk_phase += delta
	_apply_lurk_float(_lurk_anchor.y)
	_animate_lurk()

	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= detect_range:
		_target = player
		# Aus dem Wasser: aus der Ferne springen, aus der Nähe direkt beobachten.
		if dist >= leap_min_range:
			_enter_state(State.LEAP)
		else:
			_enter_state(State.OBSERVE)


func _process_leap(delta: float) -> void:
	_leap_t += delta / maxf(LEAP_DURATION, 0.001)
	_leap_t = clampf(_leap_t, 0.0, 1.0)

	# Rein kinematischer Bogen: Position DIREKT setzen, KEIN move_and_slide.
	# (Ein Sprungbogen darf nicht mit dem Boden kollidieren, den er überfliegt.)
	var flat := _leap_start.lerp(_leap_target, _leap_t)
	var arc := LEAP_ARC_HEIGHT * 4.0 * _leap_t * (1.0 - _leap_t)
	global_position = Vector3(flat.x, flat.y + arc, flat.z)
	velocity = Vector3.ZERO

	_show_leap_frame()

	# AttackArea während der Landephase aktivieren (Fisch kommt runter → trifft
	# den Player beim Aufkommen). Die Area meldet body_entered zuverlässig, auch
	# wenn der Fisch schnell durchfliegt (kein Frame-Tunneling wie beim Radius/Overlap).
	if not _leap_has_hit and _leap_t >= leap_hit_from_t:
		if not _attack_active:
			_set_attack_active(true)

	if _leap_t >= 1.0:
		# Position ist exakt _leap_target (Raycast-Bodenhöhe + Ground-Offset).
		# Kein Drop, kein Gravity-Eingriff. Sauber in LAND.
		_set_attack_active(false)
		_enter_state(State.LAND)


func _find_own_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			return child
	return null


func _process_land(delta: float) -> void:
	_show_land_frame()
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			_enter_state(State.OBSERVE)
		else:
			_enter_state(State.LURK)


func _process_observe(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.LURK)
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > lose_interest_range:
		_target = null
		_enter_state(State.LURK)
		return

	var dir := to_target.normalized()
	_update_facing_direction(dir)

	# Reaktives Ausweichen hat höchste Priorität (Player holt zum Schlag aus).
	_hop_return_state = State.OBSERVE
	if _try_reactive_hop(dist):
		return

	# Bedächtiges Spacing: zu nah → langsam zurück, zu weit → langsam ran,
	# im Toleranzband → ruhig stehen und beobachten.
	var diff := dist - preferred_distance
	if abs(diff) > preferred_distance_tolerance:
		var move := dir * signf(diff)
		if avoid_cliffs:
			var safe := _find_safe_direction(move)
			if safe != Vector3.ZERO:
				move = safe
		velocity.x = move.x * WALK_SPEED
		velocity.z = move.z * WALK_SPEED
		_animate_walk(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		_decide_next_action(dist)


## Nach einer Beobachtungsphase entscheiden: snappen, kreiseln, springen, annähern
## oder weiter beobachten. Distanzabhängig, damit der Snap tatsächlich vorkommt.
func _decide_next_action(dist: float) -> void:
	var roll := randf()

	if dist <= snap_range:
		# In Snap-Reichweite: meist snappen, sonst kreiseln/beobachten.
		if roll < snap_chance:
			_enter_state(State.SNAP_WINDUP)
		elif roll < snap_chance + circle_chance:
			_enter_state(State.CIRCLE)
		else:
			_enter_state(State.OBSERVE)
	else:
		# Außer Snap-Reichweite: annähern, springen (aus großer Distanz) oder kreiseln.
		if dist >= leap_min_range and roll < leap_chance:
			_enter_state(State.LEAP)
		elif roll < leap_chance + circle_chance:
			_enter_state(State.CIRCLE)
		else:
			_enter_state(State.APPROACH)


func _process_approach(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.LURK)
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > lose_interest_range:
		_target = null
		_enter_state(State.LURK)
		return

	var dir := to_target.normalized()
	_update_facing_direction(dir)

	# Auch beim Annähern auf Schwertschläge reagieren.
	_hop_return_state = State.OBSERVE
	if _try_reactive_hop(dist):
		return

	# In Snap-Reichweite angekommen → snappen.
	if dist <= snap_range:
		_enter_state(State.SNAP_WINDUP)
		return

	var move := dir
	if avoid_cliffs:
		var safe := _find_safe_direction(dir)
		if safe != Vector3.ZERO:
			move = safe
	velocity.x = move.x * approach_speed
	velocity.z = move.z * approach_speed
	_animate_walk(delta)

	if _check_if_stuck(delta):
		# Festgefahren → zurück ins Beobachten statt blockieren.
		_enter_state(State.OBSERVE)


func _process_circle(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.LURK)
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > lose_interest_range:
		_target = null
		_enter_state(State.LURK)
		return

	var dir_to_target := to_target.normalized()
	_update_facing_direction(dir_to_target)

	# Auch beim Kreiseln auf Schwertschläge reagieren.
	_hop_return_state = State.CIRCLE
	if _try_reactive_hop(dist):
		return

	var strafe := Vector3(-dir_to_target.z, 0, dir_to_target.x) * _circle_dir
	var diff := dist - preferred_distance
	var correction := Vector3.ZERO
	if abs(diff) > preferred_distance_tolerance:
		correction = dir_to_target * clampf(diff * 0.5, -1.0, 1.0)

	var move := (strafe + correction).normalized()
	if avoid_cliffs and _is_cliff_ahead(strafe):
		_circle_dir *= -1
		move = -strafe

	velocity.x = move.x * circle_speed
	velocity.z = move.z * circle_speed
	_animate_walk(delta)

	if _check_if_stuck(delta):
		_circle_dir *= -1

	_state_timer -= delta
	if _state_timer <= 0.0:
		_decide_next_action(dist)


func _process_snap_windup(delta: float) -> void:
	_face_target()
	_animate_snap_windup(delta)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.SNAP)


func _process_snap(delta: float) -> void:
	_show_snap_frame()

	# Kurzes Vorpreschen Richtung Player, um die Restdistanz zu überbrücken.
	if _target and is_instance_valid(_target):
		var to_t := _target.global_position - global_position
		to_t.y = 0
		if to_t.length() > snap_hit_radius * 0.8:
			_snap_dir = _snap_dir.lerp(to_t.normalized(), 0.25).normalized()
			velocity.x = _snap_dir.x * snap_advance_speed
			velocity.z = _snap_dir.z * snap_advance_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, snap_advance_speed * 3.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, snap_advance_speed * 3.0 * delta)

	# Treffer über die AttackArea (body_entered), aktiv während des Snap-Fensters.
	# (Aktivierung/Deaktivierung passiert in _enter_state SNAP bzw. SNAP_RECOVERY.)

	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.SNAP_RECOVERY)


func _process_snap_recovery(delta: float) -> void:
	_face_target()
	# In der Recovery bleibt die SNAP-Pose stehen (Maul zu / zugeschnappt), statt
	# zur Ausholpose zurückzuspringen. Sonst sieht es aus, als hole er erneut aus.
	_show_snap_frame()
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= lose_interest_range:
				_enter_state(State.OBSERVE)
				return
		_enter_state(State.LURK)


func _process_hop(delta: float) -> void:
	_hop_t += delta / maxf(hop_duration, 0.001)
	_hop_t = clampf(_hop_t, 0.0, 1.0)

	# Gewünschte Parabel-Position wie beim Leap berechnen ...
	var flat := _hop_start.lerp(_hop_target, _hop_t)
	var arc := hop_arc_height * 4.0 * _hop_t * (1.0 - _hop_t)
	var desired := Vector3(flat.x, flat.y + arc, flat.z)

	# ... aber über move_and_collide dorthin bewegen, damit der Hop an Wänden
	# STOPPT statt hindurchzuspringen (anders als der Leap, der bewusst überfliegt).
	# Ein blockierter Hop bleibt einfach an der Wand stehen – das fühlt sich beim
	# nahen Ausweichen an einem Ufer/Hindernis natürlich an.
	var motion := desired - global_position
	move_and_collide(motion)
	velocity = Vector3.ZERO

	# Während des Hops zum Player schauen (er weicht rückwärts aus) + Leap-Pose.
	_face_target()
	_show_leap_frame()

	if _hop_t >= 1.0:
		_hop_cooldown_timer = hop_cooldown
		# Zurück in den State, aus dem heraus gehoppt wurde.
		if _hop_return_state == State.CIRCLE:
			_enter_state(State.CIRCLE)
		else:
			_enter_state(State.OBSERVE)


func _process_stun(delta: float) -> void:
	_stun_timer -= delta
	_animate_hurt(delta)

	if _stun_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= lose_interest_range:
				_enter_state(State.OBSERVE)
				return
		_enter_state(State.LURK)


# === HOP HELPER ===

func _start_hop() -> void:
	var away := global_position
	if _target and is_instance_valid(_target):
		var d := global_position - _target.global_position
		d.y = 0
		if d.length() > 0.01:
			away = global_position + d.normalized() * hop_distance
	else:
		away = global_position - _facing_to_vector() * hop_distance

	# Ziel auf Bodenhöhe per Raycast + Steh-Offset (lazy gemessen, sauberes Aufsetzen).
	var gy := _raycast_ground_y(away, global_position.y + 0.5)
	if not is_nan(gy):
		away.y = gy + _get_ground_offset()
	else:
		away.y = global_position.y

	_hop_start = global_position
	_hop_target = away
	_hop_t = 0.0
	_enter_state(State.HOP)


# === LEAP HELPERS ===

func _start_leap() -> void:
	_leap_t = 0.0
	_leap_has_hit = false
	_leap_start = global_position

	var target_pos := global_position
	if _target and is_instance_valid(_target):
		target_pos = _target.global_position

	var to_target := target_pos - global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var d := flat.length()
	if d > leap_max_range:
		flat = flat.normalized() * leap_max_range

	# Ziel leicht verkürzen: landet knapp VOR dem Player.
	var shortened := maxf(flat.length() - leap_target_shorten, 0.0)
	if flat.length() > 0.01:
		flat = flat.normalized() * shortened

	_leap_target = global_position + flat

	# Landehöhe per Raycast (echte Kollision = Insel, nicht Seeboden).
	var ray_from_y := global_position.y
	var player_y := global_position.y
	if _target and is_instance_valid(_target):
		player_y = _target.global_position.y
		ray_from_y = maxf(ray_from_y, player_y)
	var landing_y := _raycast_ground_y(_leap_target, ray_from_y)
	if not is_nan(landing_y):
		# Absicherung gegen Wasser-Landung: Wenn der Raycast deutlich UNTER der
		# Player-Ebene trifft (z.B. Seeboden unter Wasser, weil das Zielfeld noch
		# über Wasser liegt), ist das kein gültiges Ziel. Dann aufs Player-Niveau
		# heben, damit der Fisch garantiert aus dem Wasser auf die Insel springt.
		if landing_y < player_y - 0.5:
			_leap_target.y = player_y + _get_ground_offset()
		else:
			_leap_target.y = landing_y + _get_ground_offset()
	else:
		_leap_target.y = ray_from_y

	if flat.length() > 0.01:
		_update_facing_direction(flat.normalized())


func _raycast_ground_y(at: Vector3, from_y: float) -> float:
	if get_world_3d() == null:
		return NAN
	var space := get_world_3d().direct_space_state
	var origin := Vector3(at.x, from_y + 2.0, at.z)
	var end := Vector3(at.x, from_y - 20.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var exclude: Array[RID] = [get_rid()]
	var player := get_player()
	if player and is_instance_valid(player) and player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space.intersect_ray(query)
	if result.is_empty():
		return NAN
	return (result.position as Vector3).y


# === FACING HELPERS ===

func _dir_to_target() -> Vector3:
	if not _target or not is_instance_valid(_target):
		return Vector3.ZERO
	var d := _target.global_position - global_position
	d.y = 0
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized()


func _face_target() -> void:
	var d := _dir_to_target()
	if d != Vector3.ZERO:
		_update_facing_direction(d)


func _facing_to_vector() -> Vector3:
	match _facing_dir:
		DirMode.RIGHT: return Vector3(1, 0, 0)
		DirMode.LEFT: return Vector3(-1, 0, 0)
		DirMode.DOWN: return Vector3(0, 0, 1)
		DirMode.UP: return Vector3(0, 0, -1)
		DirMode.DOWN_RIGHT: return Vector3(1, 0, 1).normalized()
		DirMode.DOWN_LEFT: return Vector3(-1, 0, 1).normalized()
		DirMode.UP_RIGHT: return Vector3(1, 0, -1).normalized()
		DirMode.UP_LEFT: return Vector3(-1, 0, -1).normalized()
		_: return Vector3(0, 0, 1)


func _update_facing_direction(dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		return
	var dir2d := Vector2(dir.x, dir.z)
	var angle := rad_to_deg(dir2d.angle())
	if angle < 0:
		angle += 360.0

	if angle >= 337.5 or angle < 22.5:
		_facing_dir = DirMode.RIGHT
	elif angle < 67.5:
		_facing_dir = DirMode.DOWN_RIGHT
	elif angle < 112.5:
		_facing_dir = DirMode.DOWN
	elif angle < 157.5:
		_facing_dir = DirMode.DOWN_LEFT
	elif angle < 202.5:
		_facing_dir = DirMode.LEFT
	elif angle < 247.5:
		_facing_dir = DirMode.UP_LEFT
	elif angle < 292.5:
		_facing_dir = DirMode.UP
	else:
		_facing_dir = DirMode.UP_RIGHT


# === FRAME-MAPPING (8 Richtungen → 5 Sprites, 3 gespiegelt) ===

func _single_frame(right: int, down_right: int, down: int, up_right: int, up: int) -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {frame = right, flip = false}
		DirMode.LEFT:
			return {frame = right, flip = true}
		DirMode.DOWN_RIGHT:
			return {frame = down_right, flip = false}
		DirMode.DOWN_LEFT:
			return {frame = down_right, flip = true}
		DirMode.DOWN:
			return {frame = down, flip = false}
		DirMode.UP_RIGHT:
			return {frame = up_right, flip = false}
		DirMode.UP_LEFT:
			return {frame = up_right, flip = true}
		DirMode.UP:
			return {frame = up, flip = false}
		_:
			return {frame = down, flip = false}


func _walk_frames() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {frames = WALK_RIGHT, flip = false}
		DirMode.LEFT:
			return {frames = WALK_RIGHT, flip = true}
		DirMode.DOWN_RIGHT:
			return {frames = WALK_DOWN_RIGHT, flip = false}
		DirMode.DOWN_LEFT:
			return {frames = WALK_DOWN_RIGHT, flip = true}
		DirMode.DOWN:
			return {frames = WALK_DOWN, flip = false}
		DirMode.UP_RIGHT:
			return {frames = WALK_UP_RIGHT, flip = false}
		DirMode.UP_LEFT:
			return {frames = WALK_UP_RIGHT, flip = true}
		DirMode.UP:
			return {frames = WALK_UP, flip = false}
		_:
			return {frames = WALK_DOWN, flip = false}


func _snap_windup_frames() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {frames = SNAP_WINDUP_RIGHT, flip = false}
		DirMode.LEFT:
			return {frames = SNAP_WINDUP_RIGHT, flip = true}
		DirMode.DOWN_RIGHT:
			return {frames = SNAP_WINDUP_DOWN_RIGHT, flip = false}
		DirMode.DOWN_LEFT:
			return {frames = SNAP_WINDUP_DOWN_RIGHT, flip = true}
		DirMode.DOWN:
			return {frames = SNAP_WINDUP_DOWN, flip = false}
		DirMode.UP_RIGHT:
			return {frames = SNAP_WINDUP_UP_RIGHT, flip = false}
		DirMode.UP_LEFT:
			return {frames = SNAP_WINDUP_UP_RIGHT, flip = true}
		DirMode.UP:
			return {frames = SNAP_WINDUP_UP, flip = false}
		_:
			return {frames = SNAP_WINDUP_DOWN, flip = false}


# === ANIMATION ===

func _animate_lurk() -> void:
	sprite.frame = LURK_FRAME
	sprite.flip_h = false
	sprite.modulate = sprite_modulate_override


func _animate_walk(delta: float) -> void:
	_anim_time += delta
	var data := _walk_frames()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * WALK_FPS) % frames.size()
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _animate_idle() -> void:
	var d := _single_frame(IDLE_RIGHT, IDLE_DOWN_RIGHT, IDLE_DOWN, IDLE_UP_RIGHT, IDLE_UP)
	sprite.frame = d.frame
	sprite.flip_h = d.flip
	sprite.modulate = sprite_modulate_override


func _animate_snap_windup(delta: float) -> void:
	_anim_time += delta
	var data := _snap_windup_frames()
	var frames: Array = data.frames
	var progress := clampf(_anim_time / maxf(snap_windup_time, 0.001), 0.0, 1.0)
	var idx: int = 0 if progress < 0.5 else 1
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _show_leap_frame() -> void:
	var d := _single_frame(LEAP_RIGHT, LEAP_DOWN_RIGHT, LEAP_DOWN, LEAP_UP_RIGHT, LEAP_UP)
	sprite.frame = d.frame
	sprite.flip_h = d.flip
	sprite.modulate = sprite_modulate_override


func _show_land_frame() -> void:
	var d := _single_frame(LAND_RIGHT, LAND_DOWN_RIGHT, LAND_DOWN, LAND_UP_RIGHT, LAND_UP)
	sprite.frame = d.frame
	sprite.flip_h = d.flip
	sprite.modulate = sprite_modulate_override


func _show_snap_frame() -> void:
	var d := _single_frame(SNAP_RIGHT, SNAP_DOWN_RIGHT, SNAP_DOWN, SNAP_UP_RIGHT, SNAP_UP)
	sprite.frame = d.frame
	sprite.flip_h = d.flip
	sprite.modulate = sprite_modulate_override


func _animate_hurt(delta: float) -> void:
	_anim_time += delta
	var d := _single_frame(HURT_RIGHT, HURT_DOWN_RIGHT, HURT_DOWN, HURT_UP_RIGHT, HURT_UP)
	sprite.frame = d.frame
	sprite.flip_h = d.flip
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else sprite_modulate_override
