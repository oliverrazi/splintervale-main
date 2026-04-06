## GlobalCaveData — Autoload singleton that persists cave transition state.
##
## Register this as an Autoload in Project → Project Settings → Autoload.
## Name it "GlobalCaveData". This stores transition data between the overworld
## and cave scenes so the cave knows where to spawn the player and the
## overworld knows where to return them.

extends Node

## The spawn point ID the player should appear at in the cave.
var pending_spawn_id: String = ""

## The overworld position the player entered the cave from (for return trips).
var return_position: Vector3 = Vector3.ZERO

## The scene path to return to when exiting the cave.
var return_scene_path: String = ""

## Which cave floor/level the player is on (for multi-level caves).
var current_cave_depth: int = 0

## Persistent cave state — tracks which items have been collected, doors opened, etc.
## Key format: "cave_id:object_id" → value (bool, int, etc.)
var cave_state: Dictionary = {}

## Player state snapshot taken before entering cave (for restoration on exit).
var player_state_snapshot: Dictionary = {}


## Save a flag for a specific cave object (e.g., chest opened, crystal collected).
func set_cave_flag(cave_id: String, object_id: String, value: Variant) -> void:
	var key := "%s:%s" % [cave_id, object_id]
	cave_state[key] = value


## Read a cave object flag. Returns [param default] if not set.
func get_cave_flag(cave_id: String, object_id: String, default: Variant = false) -> Variant:
	var key := "%s:%s" % [cave_id, object_id]
	return cave_state.get(key, default)


## Take a snapshot of the player's state before entering a cave.
func snapshot_player(player: Node3D) -> void:
	player_state_snapshot = {
		"health": player.get("health") if player.get("health") != null else -1,
		"position": player.global_position,
	}


## Clear all temporary transition data (call after spawn is complete).
func clear_transition() -> void:
	pending_spawn_id = ""
	# Keep return data — needed for cave exit.


## Full reset (e.g., on game over or main menu return).
func reset_all() -> void:
	pending_spawn_id = ""
	return_position = Vector3.ZERO
	return_scene_path = ""
	current_cave_depth = 0
	cave_state.clear()
	player_state_snapshot.clear()
