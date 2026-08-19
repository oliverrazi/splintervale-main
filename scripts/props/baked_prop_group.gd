@tool
class_name BakedPropGroup
extends Resource

## Eine gebakte Modell-Gruppe: MultiMesh (Darstellung), geteilte Collision-Shape
## und deren Instanz-Transforms, plus das beim Bake eingefrorene Material.
##
## WICHTIG (v2): material haelt das Surface-Override-/Instanz-Material der Quell-
## MeshInstance3D fest. MultiMeshInstance3D rendert NICHT die Per-Instance-
## Overrides der urspruenglichen Nodes - ohne dieses Feld waeren gebakte Props
## materiallos (weiss). Das Runtime setzt es als material_override aufs MMI.

@export var source_mesh_path: String = ""
@export var multimesh: MultiMesh
@export var collision_shape: Shape3D
@export var transforms: Array[Transform3D] = []

## Beim Bake abgegriffenes Material der Quell-Instanzen (Override oder Mesh-Mat).
## Kann null sein, wenn das Mesh sein Material bereits selbst traegt UND kein
## Override existierte - dann rendert das MMI korrekt aus dem Mesh.
@export var material: Material
