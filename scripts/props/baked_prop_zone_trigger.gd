extends Area3D

## Beispiel-Zone-Trigger fuer eine gebakte Prop-Gruppe.
## Haengt an einem Area3D, das den Bereich umschliesst.
## Aktiviert den zugewiesenen BakedPropRuntime beim Player-Eintritt.

## Der Runtime-Node, der ein-/ausgeblendet wird. Im Inspector zuweisen.
@export var prop_runtime: BakedPropRuntime

## Nur dieser Body loest aus (dein Player). Im Inspector zuweisen,
## oder leer lassen und den Player in Gruppe "player" stecken.
@export var player: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if _is_player(body) and prop_runtime != null:
		prop_runtime.set_active(true)


func _on_body_exited(body: Node3D) -> void:
	if _is_player(body) and prop_runtime != null:
		prop_runtime.set_active(false)


func _is_player(body: Node3D) -> bool:
	if player != null:
		return body == player
	return body.is_in_group("player")
