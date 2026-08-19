class_name FloatingPlatformGroup
extends Node3D
## Gemeinsame Steuerung für mehrere schwimmende Plattformen auf EINEM Fluss.
## Die zwei Marker definieren nur die Z-Spanne (Flussachse); X/Y der Marker werden ignoriert.
## Alle Plattformen teilen Z-Grenzen, Speed und Timing -> gleiche Loop-Periode
## -> der Z-Abstand zwischen Plattformen bleibt für immer konstant (kein Auseinanderdriften).
## Jede Plattform behält ihr eigenes authored X und Y (Höhe frei pro Plattform).

## Flussanfang – hier tauchen Plattformen wieder auf. Nur Z zählt.
@export var spawn_point: Node3D
## Flussende – hier tauchen Plattformen ab und loopen zurück. Nur Z zählt.
@export var despawn_point: Node3D

@export_group("Fluss")
## Drift-Geschwindigkeit entlang Z in m/s (sichtbare Fahrt), geteilt von allen Plattformen.
@export var drift_speed: float = 0.8

@export_group("Loop-Timing")
## Wie tief (Welt-Y) eine Plattform beim Loop abtaucht, bis der Player sie nicht mehr sieht.
@export var dip_depth: float = 3.0
## Dauer des Abtauchens am Despawn (Sekunden).
@export var dive_time: float = 0.6
## Dauer der verdeckten Rückfahrt Despawn -> Spawn. Klein = "schießt schnell zurück".
@export var return_time: float = 0.5
## Dauer des Auftauchens am Spawn (Sekunden).
@export var surface_time: float = 0.6

@export_group("Schaukeln")
@export var bob_amplitude: float = 0.06
@export var bob_frequency: float = 0.6
@export var roll_amplitude_deg: float = 2.5
@export var roll_frequency: float = 0.45
@export var pitch_amplitude_deg: float = 1.5
@export var pitch_frequency: float = 0.37
@export var randomize_phase: bool = true


func _ready() -> void:
	if not has_valid_markers():
		push_warning("FloatingPlatformGroup: spawn_point/despawn_point nicht gesetzt.")


func has_valid_markers() -> bool:
	return spawn_point != null and despawn_point != null


func get_spawn_z() -> float:
	return spawn_point.global_position.z


func get_despawn_z() -> float:
	return despawn_point.global_position.z
