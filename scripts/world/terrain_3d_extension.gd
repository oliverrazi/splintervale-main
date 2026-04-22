extends Node3D

@onready var terrain: Terrain3D = $Terrain3D  # Pfad anpassen falls anders

func _ready() -> void:
	print("=== Terrain Setup ===")
	print("terrain node: ", terrain)
	if terrain:
		print("terrain class: ", terrain.get_class())
		print("properties:")
		for prop in terrain.get_property_list():
			var name: String = prop.name
			if "target" in name.to_lower() or "collision" in name.to_lower() or "player" in name.to_lower():
				print("  - ", name, " = ", terrain.get(name))
	
	_try_attach_player()


func _try_attach_player() -> void:
	for i in range(30):
		var player := get_tree().get_first_node_in_group("player")
		if player and terrain:
			print("Frame ", i, ": Player gefunden, Terrain bereit")
			print("  Player pos: ", player.global_position)
			# Hier alle möglichen Property-Namen ausprobieren
			for prop_name in ["collision_target", "target", "player", "collision_follow_target"]:
				if prop_name in terrain:
					print("  → setze '", prop_name, "' = player")
					terrain.set(prop_name, player)
			return
		await get_tree().process_frame
	print("Player nicht gefunden nach 30 Frames!")
