@tool
extends Resource
class_name GrassBakeData
## Vorberechnete Grasdaten einer GrassSystem-Fläche.
## Wird per Bake-Knopf im Editor erzeugt und beim Spielstart geladen, statt
## das Gras teuer neu zu generieren. Enthält die fertigen MultiMesh-Buffer
## pro (Chunk x Profil) plus die zugehörigen AABBs.
##
## Speicherformat: Arrays parallel indiziert. Jeder Eintrag i beschreibt einen
## MultiMeshInstance3D (ein Chunk-Surface eines Profils).

## Profil-Index pro Eintrag (welches Material/Shader genutzt wird).
@export var profile_indices: PackedInt32Array = PackedInt32Array()
## Instanzzahl pro Eintrag.
@export var counts: PackedInt32Array = PackedInt32Array()
## AABB-Ursprung pro Eintrag (lokal zur GrassSystem-Node).
@export var aabb_positions: PackedVector3Array = PackedVector3Array()
## AABB-Größe pro Eintrag.
@export var aabb_sizes: PackedVector3Array = PackedVector3Array()
## Die fertigen interleaved MultiMesh-Buffer (ein PackedFloat32Array je Eintrag).
## Als Array gespeichert, weil verschachtelte PackedArrays nicht direkt gehen.
@export var buffers: Array = []

## Metadaten zur Validierung (damit ein veralteter Bake erkannt werden kann).
@export var total_instances: int = 0
@export var profile_count: int = 0
@export var bake_version: int = 1


## Hängt einen fertigen Eintrag an.
func add_entry(profile_index: int, count: int, aabb: AABB, buffer: PackedFloat32Array) -> void:
	profile_indices.append(profile_index)
	counts.append(count)
	aabb_positions.append(aabb.position)
	aabb_sizes.append(aabb.size)
	buffers.append(buffer)
	total_instances += count


func entry_count() -> int:
	return counts.size()
