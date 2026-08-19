extends RefCounted
class_name SynergyResult

## Ergebnis eines plan_synergy()-Aufrufs. Rein informativ — wird beim CAST
## (nicht beim Hit) an die anfragende Component zurückgegeben, damit sie die
## Kosten berechnen und den Schadens-Multiplier für DIESE Synergie kennt.
##
## allowed ist praktisch immer true, bleibt aber
## als sauberer Hook erhalten (z.B. falls später doch mal ein Block nötig wird).

## Darf die Synergie ausgeführt werden? (Aktuell immer true.)
var allowed: bool = true

## Combo-Stand, DEN diese Synergie erreichen wird, wenn sie trifft (= aktueller
## Combo + 1). Für Schadensberechnung und UI-Vorschau.
var combo_count: int = 0

## Schadens-Multiplier für diese Synergie (basiert auf combo_count).
var damage_multiplier: float = 1.0

## Zusätzliche RP-Kosten OBEN DRAUF auf die eigene Basis-Kost der Component.
## Steigt linear mit der Chain-Position: erster Cast 0, dann +surcharge, +2×, …
var cost_surcharge: float = 0.0


func _to_string() -> String:
	return "[SynergyResult allowed=%s combo=%d mult=%.2fx surcharge=%.1f]" % [
		allowed, combo_count, damage_multiplier, cost_surcharge
	]
