@tool
class_name BakedPropData
extends Resource

## Komplettes Bake-Ergebnis fuer eine Prop-Gruppe (ein Bereich/eine Art).
## Eine BakedPropGroup pro einzigartigem Mesh-Modell.

@export var groups: Array[BakedPropGroup] = []
