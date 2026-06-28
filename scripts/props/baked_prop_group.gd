@tool
class_name BakedPropGroup
extends Resource

## Alles, was zu EINEM Prop-Modell gehoert (Wand, Farn, Felsen, ...).
## Pro einzigartigem Mesh genau eine Gruppe -> genau ein Draw Call (pro Surface).

## MultiMesh: traegt Mesh + alle Instance-Transforms + Color-Buffer.
@export var multimesh: MultiMesh

## Fertig gecookte Collision-Shape fuer dieses Modell, oder null (keine Collision).
## ConvexPolygonShape3D (billig) ODER ConcavePolygonShape3D (Trimesh, genau).
## Beim Bake erzeugt und serialisiert -> Laufzeit weist nur noch zu, kein Cook.
@export var collision_shape: Shape3D

## Quell-Pfad des Meshes, rein zur Anzeige/Debug.
@export var source_mesh_path: String = ""

## Globale (baker-lokale) Transforms pro Instanz fuer die CollisionShape3Ds.
@export var transforms: Array[Transform3D] = []
