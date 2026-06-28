class_name WaterPlantChunk
extends Resource

## Ein einzelner raeumlicher Chunk: eine MultiMesh plus ihre eigene AABB.
## Die AABB ist klein (nur dieser Chunk) -> erlaubt praezises Frustum-Culling.

@export var multimesh: MultiMesh
@export var aabb: AABB
