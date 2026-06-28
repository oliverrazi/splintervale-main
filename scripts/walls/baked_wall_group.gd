@tool
class_name BakedWallGroup
extends Resource

## Alles, was zu EINEM Wand-Modell gehoert.
## Pro einzigartigem Mesh genau eine Gruppe -> genau ein Draw Call (pro Surface).

## MultiMesh: traegt Mesh + alle Instance-Transforms + Color-Buffer.
@export var multimesh: MultiMesh

## Fertig gecookte Collision-Shape fuer dieses Modell.
## ConvexPolygonShape3D (billig, glatte Waende) ODER
## ConcavePolygonShape3D (Trimesh, genau, fuer konkave Waende).
## Beim Bake erzeugt und serialisiert -> Laufzeit weist nur noch zu, kein Cook.
@export var collision_shape: Shape3D

## Quell-Pfad des Meshes, rein zur Anzeige/Debug im gebakten Asset.
@export var source_mesh_path: String = ""

## Globale (baker-lokale) Transforms pro Instanz fuer die CollisionShape3Ds.
@export var transforms: Array[Transform3D] = []
