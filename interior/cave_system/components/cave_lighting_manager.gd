## CaveLightingManager — Manages all dynamic light sources in the cave.
##
## Handles torch flickering, crystal glow pulsing, proximity-based light
## activation (for performance), and overall cave lighting mood.
##
## Add individual light sources as children of this node, or use the
## helper methods to create common light types.

class_name CaveLightingManager
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Performance")
## Maximum lights active simultaneously. Lights beyond this are disabled.
@export var max_active_lights: int = 12
## Radius around the player where lights are activated.
@export var activation_radius: float = 18.0
## How often to recalculate which lights are active (seconds).
@export var update_interval: float = 0.3

@export_group("Torch Defaults")
@export var torch_color: Color = Color(1.0, 0.7, 0.35)
@export var torch_energy: float = 1.2
@export var torch_range: float = 6.0
@export var torch_flicker_speed: float = 8.0
@export var torch_flicker_intensity: float = 0.15

@export_group("Crystal Defaults")
@export var crystal_color: Color = Color(0.3, 0.7, 1.0)
@export var crystal_energy: float = 0.6
@export var crystal_range: float = 4.0
@export var crystal_pulse_speed: float = 1.5
@export var crystal_pulse_intensity: float = 0.3

# ── Internal State ────────────────────────────────────────────────────────────

var _managed_lights: Array[Dictionary] = []
# Each entry: { "node": OmniLight3D, "type": String, "base_energy": float, "phase": float }

var _update_timer: float = 0.0
var _player: Node3D


func _ready() -> void:
	# Register any pre-existing OmniLight3D children
	for child in get_children():
		if child is OmniLight3D:
			_register_existing_light(child)


func _process(delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")

	# Proximity culling
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_light_activation()

	# Animate active lights
	for entry in _managed_lights:
		var light: OmniLight3D = entry["node"]
		if not light.visible:
			continue

		match entry["type"]:
			"torch":
				_animate_torch(light, entry, delta)
			"crystal":
				_animate_crystal(light, entry, delta)
			"pulse":
				_animate_pulse(light, entry, delta)


# ── Light Creation Helpers ────────────────────────────────────────────────────

## Create a torch light at the given position. Returns the OmniLight3D.
func add_torch(pos: Vector3, color_override: Color = Color(-1, 0, 0),
		energy_override: float = -1.0, range_override: float = -1.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color_override if color_override.r >= 0 else torch_color
	light.light_energy = energy_override if energy_override > 0 else torch_energy
	light.omni_range = range_override if range_override > 0 else torch_range
	light.omni_attenuation = 1.5
	light.shadow_enabled = false  # Perf: disable for most torches
	light.position = pos

	add_child(light)
	_managed_lights.append({
		"node": light,
		"type": "torch",
		"base_energy": light.light_energy,
		"phase": randf() * TAU,  # Random phase so torches don't flicker in sync
	})
	return light


## Create a crystal glow at the given position. Returns the OmniLight3D.
func add_crystal_light(pos: Vector3, color_override: Color = Color(-1, 0, 0),
		energy_override: float = -1.0, range_override: float = -1.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color_override if color_override.r >= 0 else crystal_color
	light.light_energy = energy_override if energy_override > 0 else crystal_energy
	light.omni_range = range_override if range_override > 0 else crystal_range
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	light.position = pos

	add_child(light)
	_managed_lights.append({
		"node": light,
		"type": "crystal",
		"base_energy": light.light_energy,
		"phase": randf() * TAU,
	})
	return light


## Create a generic pulsing light (for bioluminescent plants, etc.).
func add_pulse_light(pos: Vector3, color: Color, energy: float = 0.4,
		light_range: float = 3.0, pulse_speed: float = 2.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.position = pos

	add_child(light)
	_managed_lights.append({
		"node": light,
		"type": "pulse",
		"base_energy": energy,
		"phase": randf() * TAU,
		"speed": pulse_speed,
	})
	return light


# ── Light Animation ───────────────────────────────────────────────────────────

func _animate_torch(light: OmniLight3D, entry: Dictionary, _delta: float) -> void:
	var phase: float = entry["phase"]
	var base: float = entry["base_energy"]
	var t: float = (Time.get_ticks_msec() / 1000.0) * torch_flicker_speed + phase

	# Multi-frequency flicker for realistic fire
	var flicker := sin(t) * 0.4 + sin(t * 2.7) * 0.3 + sin(t * 4.1) * 0.2 + sin(t * 7.3) * 0.1
	flicker *= torch_flicker_intensity

	light.light_energy = base + flicker * base

	# Subtle color temperature shift
	var warm_shift := flicker * 0.05
	light.light_color = torch_color + Color(warm_shift, -warm_shift * 0.5, -warm_shift)


func _animate_crystal(light: OmniLight3D, entry: Dictionary, _delta: float) -> void:
	var phase: float = entry["phase"]
	var base: float = entry["base_energy"]
	var t: float = (Time.get_ticks_msec() / 1000.0) * crystal_pulse_speed + phase

	# Smooth sinusoidal pulse
	var pulse := (sin(t) + 1.0) * 0.5  # 0 to 1
	pulse = smoothstep(0.2, 0.8, pulse)  # Ease the curve

	light.light_energy = base * (1.0 - crystal_pulse_intensity + pulse * crystal_pulse_intensity)


func _animate_pulse(light: OmniLight3D, entry: Dictionary, _delta: float) -> void:
	var phase: float = entry["phase"]
	var base: float = entry["base_energy"]
	var speed: float = entry.get("speed", 2.0)
	var t: float = (Time.get_ticks_msec() / 1000.0) * speed + phase

	var pulse := (sin(t) + 1.0) * 0.5
	light.light_energy = base * (0.3 + pulse * 0.7)


# ── Performance: Proximity Culling ────────────────────────────────────────────

func _update_light_activation() -> void:
	if not _player:
		return

	var player_pos := _player.global_position

	# Sort by distance to player
	var sorted_entries: Array[Dictionary] = _managed_lights.duplicate()
	sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var dist_a: float = a["node"].global_position.distance_squared_to(player_pos)
		var dist_b: float = b["node"].global_position.distance_squared_to(player_pos)
		return dist_a < dist_b
	)

	var active_count: int = 0
	var radius_sq := activation_radius * activation_radius

	for entry in sorted_entries:
		var light: OmniLight3D = entry["node"]
		var dist_sq := light.global_position.distance_squared_to(player_pos)

		if dist_sq <= radius_sq and active_count < max_active_lights:
			light.visible = true
			active_count += 1
		else:
			light.visible = false


func _register_existing_light(light: OmniLight3D) -> void:
	# Try to auto-detect type from node name
	var ltype := "torch"
	var lname := light.name.to_lower()
	if "crystal" in lname:
		ltype = "crystal"
	elif "pulse" in lname or "glow" in lname or "bio" in lname:
		ltype = "pulse"

	_managed_lights.append({
		"node": light,
		"type": ltype,
		"base_energy": light.light_energy,
		"phase": randf() * TAU,
	})
