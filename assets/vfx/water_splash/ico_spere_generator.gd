@tool
class_name IcoSphereGenerator
extends MeshInstance3D
## Generiert eine IcoSphere für Wasserkugel-Partikel.
## Gleichmäßige Vertex-Verteilung (kein Pol-Clustering wie SphereMesh),
## damit die Noise-Verzerrung überall gleich wabbelt.

@export var radius: float = 0.04 : set = _set_radius
@export var subdivisions: int = 2 : set = _set_subdiv  ## 2 = 320 Tris, reicht für kleine Blobs
@export var regenerate: bool = false : set = _do_regen

func _set_radius(v: float) -> void:
	radius = v
	_build()

func _set_subdiv(v: int) -> void:
	subdivisions = clampi(v, 0, 4)
	_build()

func _do_regen(_v: bool) -> void:
	_build()

func _ready() -> void:
	if mesh == null:
		_build()

func _build() -> void:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)
	]
	for i in range(verts.size()):
		verts[i] = verts[i].normalized()

	var faces: Array = [
		[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
		[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
		[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
		[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]
	]

	# Subdivision
	for s in range(subdivisions):
		var new_faces: Array = []
		var midpoint_cache: Dictionary = {}
		for f in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			var ab: int = _midpoint(a, b, verts, midpoint_cache)
			var bc: int = _midpoint(b, c, verts, midpoint_cache)
			var ca: int = _midpoint(c, a, verts, midpoint_cache)
			new_faces.append([a, ab, ca])
			new_faces.append([b, bc, ab])
			new_faces.append([c, ca, bc])
			new_faces.append([ab, bc, ca])
		faces = new_faces

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		for idx in f:
			var v: Vector3 = verts[idx]
			st.set_normal(v)
			# UV aus Kugelkoordinaten (für Noise-Sampling)
			var u: float = 0.5 + atan2(v.z, v.x) / TAU
			var vv: float = 0.5 - asin(v.y) / PI
			st.set_uv(Vector2(u, vv))
			st.add_vertex(v * radius)
	mesh = st.commit()

func _midpoint(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var key: String = str(mini(a, b)) + "_" + str(maxi(a, b))
	if cache.has(key):
		return cache[key]
	var mid: Vector3 = ((verts[a] + verts[b]) * 0.5).normalized()
	verts.append(mid)
	var idx: int = verts.size() - 1
	cache[key] = idx
	return idx
