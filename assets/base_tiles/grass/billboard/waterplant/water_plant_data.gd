class_name WaterPlantData
extends Resource

## Gebakenes Ergebnis mit raeumlichem Chunking.
## Statt einer einzigen MultiMesh haelt die Data ein Array von Chunks -
## jeder Chunk eine eigene MultiMesh mit eigener (kleiner) AABB. Zur Laufzeit
## cullt Godot jeden Chunk einzeln, entfernte Chunks kosten nichts.
## Das Material wird GETEILT (eine globale Welle fuer alle Chunks).

@export var chunks: Array[WaterPlantChunk] = []
@export var material: ShaderMaterial
@export var bounds_aabb: AABB          # Gesamt-Bounds ueber alle Chunks (Info/Debug)
@export var instance_count: int = 0    # Gesamtzahl Pflanzen ueber alle Chunks
