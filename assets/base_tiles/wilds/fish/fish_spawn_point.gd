## FishSpawnPoint
##
## Ein Marker3D, der einen Fisch-Spawn definiert. Im Editor platzierbar,
## zeigt ein Gizmo (Radius-Ring) zur Orientierung. Der FishManager sammelt
## alle FishSpawnPoint-Kinder ein und spawnt deren Fische.
##
## Die Y-Position DIESES Markers ist die feste Schwebehöhe der Fische.
## Du setzt den Marker also einfach auf die gewünschte Höhe im Wasser.

@tool
class_name FishSpawnPoint
extends Marker3D

## Wie viele Fische hier spawnen. 1 = Einzelgänger, >1 = Gruppe.
@export var count: int = 6

## Radius, in dem sich die Fische frei bewegen (Heimat-Areal).
## Sie dürfen kurz darüber hinaus, werden aber sanft zurückgezogen.
@export var radius: float = 3.0

## true = schwärmen (Alignment+Cohesion). false = jeder für sich.
## Bei count == 1 wird das ignoriert (immer Einzelgänger).
@export var schooling: bool = true

## Optionaler eigener Seed für reproduzierbare Verteilung (0 = zufällig).
@export var spawn_seed: int = 0


# --- Editor-Gizmo: Radius-Ring zeichnen ---
func _ready() -> void:
	if Engine.is_editor_hint():
		# Gizmo-Update anstoßen, wenn sich Properties ändern.
		set_notify_transform(true)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if count < 1:
		warnings.append("count sollte mindestens 1 sein.")
	if radius <= 0.0:
		warnings.append("radius muss > 0 sein.")
	return warnings
