extends Area3D

## Beispiel-Zone-Trigger fuer eine gebakte Wand-Verkleidung.
## Haengt an einem Area3D, das den Bereich umschliesst.
## Aktiviert den zugewiesenen BakedWallRuntime beim Player-Eintritt.

## Der Runtime-Node, der ein-/ausgeblendet wird. Im Inspector zuweisen.
@export var wall_runtime: BakedWallRuntime

## Nur dieser Body loest aus (dein Player). Im Inspector zuweisen,
## oder per Group-Check ersetzen (siehe _is_player).
@export var player: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if _is_player(body) and wall_runtime != null:
		wall_runtime.set_active(true)


func _on_body_exited(body: Node3D) -> void:
	if _is_player(body) and wall_runtime != null:
		wall_runtime.set_active(false)


func _is_player(body: Node3D) -> bool:
	# Variante A: direkte Referenz.
	if player != null:
		return body == player
	# Variante B (Fallback): Group-Check. Dann den Player in Gruppe "player" stecken.
	return body.is_in_group("player")
