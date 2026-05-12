extends RefCounted
class_name SynergyResult

## Ergebnis einer Synergie-Anfrage. Wird vom SynergyManager an die
## anfragende Component zurückgegeben.

## Darf die Synergie überhaupt ausgeführt werden?
var allowed: bool = true

## Damage-Multiplikator. Standard 1.0, kann auch unter 1.0 sein bei Penalty.
var damage_multiplier: float = 1.0

## Aktueller Combo-Stand nach diesem Use (für UI).
var combo_count: int = 0

## Wurde mit diesem Use Overheat ausgelöst?
var triggered_overheat: bool = false

## Klassifikation für Logging/Debugging
enum Reason { FRESH, VARIATION, REPEAT_IN_HISTORY, DIRECT_REPEAT, BLOCKED_OVERHEAT }
var reason: Reason = Reason.FRESH


func _to_string() -> String:
	var reason_name: String = ["FRESH", "VARIATION", "REPEAT_IN_HISTORY", "DIRECT_REPEAT", "BLOCKED_OVERHEAT"][reason]
	return "[SynergyResult allowed=%s mult=%.2fx combo=%d overheat=%s reason=%s]" % [
		allowed, damage_multiplier, combo_count, triggered_overheat, reason_name
	]
