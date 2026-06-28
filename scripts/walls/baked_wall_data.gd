@tool
class_name BakedWallData
extends Resource

## Komplettes Bake-Ergebnis fuer eine Wand-Verkleidung (ein Bereich).
## Eine BakedWallGroup pro einzigartigem Mesh-Modell.

@export var groups: Array[BakedWallGroup] = []
