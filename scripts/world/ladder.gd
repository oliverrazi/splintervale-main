class_name Ladder
extends Node3D

## Leiter-Scene. Aufbau:
## Ladder (Node3D)
## ├── MeshInstance3D        (dein Blender-Modell)
## ├── ClimbZone (Area3D)    ← BoxShape über die volle Leiterhöhe, vor der Leiter
## ├── TopZone (Area3D)      ← kleine Box AUF dem oberen Ledge, an der Kante
## ├── BottomMarker (Marker3D) ← Fußpunkt: wo der Player beim Klettern steht (X/Z-Linie + unteres Y)
## ├── TopMarker (Marker3D)    ← oberster Kletterpunkt (gleiche X/Z, oberes Y)
## └── TopExit (Marker3D)      ← Ausstiegsposition auf dem Ledge (klar hinter der Kante)

@onready var bottom_marker: Marker3D = $BottomMarker
@onready var top_marker: Marker3D = $TopMarker
@onready var top_exit: Marker3D = $TopExit


func _ready() -> void:
	$ClimbZone.body_entered.connect(_on_climb_entered)
	$ClimbZone.body_exited.connect(_on_climb_exited)
	$TopZone.body_entered.connect(_on_top_entered)
	$TopZone.body_exited.connect(_on_top_exited)


func _get_ladder_component(body: Node) -> LadderComponent:
	if not body.is_in_group("player"):
		return null
	return body.get_node_or_null("LadderComponent") as LadderComponent


func _on_climb_entered(body: Node3D) -> void:
	var comp := _get_ladder_component(body)
	if comp:
		comp.set_nearby_ladder(self)


func _on_climb_exited(body: Node3D) -> void:
	var comp := _get_ladder_component(body)
	if comp:
		comp.clear_nearby_ladder(self)


func _on_top_entered(body: Node3D) -> void:
	var comp := _get_ladder_component(body)
	if comp:
		comp.set_top_ladder(self)


func _on_top_exited(body: Node3D) -> void:
	var comp := _get_ladder_component(body)
	if comp:
		comp.clear_top_ladder(self)


# ─── Geometrie-Getter ───

func get_bottom_y() -> float:
	return bottom_marker.global_position.y


func get_top_y() -> float:
	return top_marker.global_position.y


func get_line_position() -> Vector3:
	## X/Z-Linie, auf die der Player beim Klettern gesnapped wird
	return bottom_marker.global_position


func get_top_exit_position() -> Vector3:
	return top_exit.global_position
