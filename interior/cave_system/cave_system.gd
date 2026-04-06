## CaveSystem — Main controller for a cave scene.
##
## This is the root script for any cave scene. It handles:
##   • Player spawning at the correct entrance point
##   • Fade-in from black on entry
##   • Environment / atmosphere setup
##   • Cave exit back to the overworld
##   • Audio ambience management
##
## Scene tree expectation:
##   CaveSystem (this script)
##   ├── WorldEnvironment
##   ├── CaveCamera (Camera3D or your camera rig)
##   ├── CaveFloor (Node3D — holds all floor MeshInstance3Ds)
##   ├── CaveWalls (Node3D — holds wall edge meshes / sprites)
##   ├── CaveDecorations (Node3D — stalactites, crystals, moss, etc.)
##   ├── CaveWater (Node3D — streams, puddles)
##   ├── CaveLighting (Node3D — lights, torches, crystals)
##   ├── UnreachableAreas (Node3D — visible but non-navigable scenery)
##   ├── SpawnPoints (Node3D — Marker3D children named by ID)
##   ├── Navigation (NavigationRegion3D)
##   ├── Collision (StaticBody3D with CollisionPolygon3D / shapes)
##   └── CaveExits (Node3D — Area3D triggers leading out)

class_name CaveSystem
extends Node3D

## Unique identifier for this cave (used in save state keys).
@export var cave_id: String = "cave_01"

## Fade-in duration when entering the cave.
@export var fade_in_duration: float = 1.0

## Base ambient light color inside the cave.
@export var ambient_color: Color = Color(0.06, 0.065, 0.08)

## Ambient light energy — keep low for dark caves, raise for luminous ones.
@export_range(0.0, 1.0) var ambient_energy: float = 0.15

## Enable distance-based audio reverb for cave echo effect.
@export var enable_reverb: bool = true

## Reverb bus name (set up an AudioBus with Reverb effect).
@export var reverb_bus: String = "CaveReverb"

# ── Node References ───────────────────────────────────────────────────────────

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var spawn_points: Node3D = $SpawnPoints
@onready var cave_atmosphere: CaveAtmosphere = $CaveAtmosphere if has_node("CaveAtmosphere") else null

var _fade_overlay: ColorRect
var _player: Node3D


func _ready() -> void:
	_setup_environment()
	_setup_fade_overlay()
	_apply_cave_state()

	if enable_reverb:
		_setup_audio_reverb()

	# Wait for PlayerManager autoload to add the player
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_player()
	_fade_in()


# ── Environment ───────────────────────────────────────────────────────────────

func _setup_environment() -> void:
	if not world_env:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		add_child(world_env)

	var env := world_env.environment
	if not env:
		env = Environment.new()
		world_env.environment = env

	# Black background — the void outside the cave
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK

	# Ambient light — very dim, cool tones
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy

	# Tonemap for mood
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2

	# Subtle glow for light sources (crystals, torches)
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.8
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)

	# SSAO for depth in crevices (if performance allows)
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.5

	# Fog — subtle depth fog for atmosphere
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.045, 0.06)
	env.fog_density = 0.015
	env.fog_light_energy = 0.2


# ── Player Spawning ───────────────────────────────────────────────────────────

func _spawn_player() -> void:
	_player = get_tree().get_first_node_in_group("player")

	if not _player:
		push_warning("CaveSystem: No player found in group 'player'. "
			+ "Make sure the player scene is instanced and in the 'player' group.")
		return

	# Find the correct spawn point
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	var spawn_id: String = cave_data.pending_spawn_id if cave_data else ""
	var spawn_marker: Marker3D = null

	if not spawn_id.is_empty() and spawn_points:
		spawn_marker = spawn_points.get_node_or_null(spawn_id) as Marker3D

	if not spawn_marker and spawn_points and spawn_points.get_child_count() > 0:
		spawn_marker = spawn_points.get_child(0) as Marker3D
		if spawn_id:
			push_warning("CaveSystem: Spawn point '%s' not found, using first available." % spawn_id)

	if spawn_marker:
		_player.global_position = spawn_marker.global_position
		# Face the player in the marker's forward direction
		_player.global_rotation.y = spawn_marker.global_rotation.y

	if cave_data and cave_data.has_method("clear_transition"):
		cave_data.clear_transition()

	# Re-enable player input
	if _player.has_method("set_input_enabled"):
		_player.set_input_enabled(true)


# ── Cave State (Persistence) ─────────────────────────────────────────────────

func _apply_cave_state() -> void:
	## Iterate over all objects that care about persistent state.
	## Objects should implement `restore_cave_state(cave_id: String)`.
	for child in _get_all_descendants(self):
		if child.has_method("restore_cave_state"):
			child.restore_cave_state(cave_id)


func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result


# ── Transitions ───────────────────────────────────────────────────────────────

func _setup_fade_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100

	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 1)  # Start fully black
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	canvas.add_child(_fade_overlay)
	add_child(canvas)


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, fade_in_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Don't free — we need it for exit_cave()
	tween.tween_callback(func(): _fade_overlay.visible = false)


## Call this from a CaveExit Area3D to return to the overworld.
func exit_cave() -> void:
	if _player and _player.has_method("set_input_enabled"):
		_player.set_input_enabled(false)

	# Ensure overlay is visible and usable
	if not is_instance_valid(_fade_overlay):
		_setup_fade_overlay()
	_fade_overlay.visible = true
	_fade_overlay.color.a = 0.0

	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, 0.8)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_return_to_overworld)


func _return_to_overworld() -> void:
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	var return_path: String = cave_data.return_scene_path if cave_data else ""
	if return_path.is_empty():
		push_error("CaveSystem: No return scene path set in GlobalCaveData!")
		return
	get_tree().change_scene_to_file(return_path)


# ── Audio ─────────────────────────────────────────────────────────────────────

func _setup_audio_reverb() -> void:
	# Check if the reverb bus exists
	var bus_idx := AudioServer.get_bus_index(reverb_bus)
	if bus_idx == -1:
		push_warning("CaveSystem: Audio bus '%s' not found. "
			+ "Create a bus named '%s' with a Reverb effect for cave echo." 
			% [reverb_bus, reverb_bus])
		return

	# All AudioStreamPlayers in the cave should route to this bus.
	# This is handled per-player, but we can set a default.
	# Typically you'd set this on your SFX players.
