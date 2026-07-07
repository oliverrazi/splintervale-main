@tool
class_name CrownLeafGenerator
extends MeshInstance3D
## Generiert eine Wind-Waker-artige Splash-Crown aus N gewölbten Wasserblättern.
## An der Basis verbunden, oben in klare Blätter gespreizt.
## UV.y: 0 = Basis, 1 = Blattspitze (für Aufstiegs-Animation im Shader).
## UV.x: 0..1 quer über jedes Blatt (für die Blatt-Silhouette).

@export var leaf_count: int = 7 : set = _set_leaf_count
@export var rings: int = 5 : set = _set_rings
@export var base_radius: float = 0.05 : set = _set_base_radius
@export var top_radius: float = 0.16 : set = _set_top_radius
@export var crown_height: float = 0.20 : set = _set_height
@export var curve: float = 0.06 : set = _set_curve
@export var leaf_fill: float = 0.7 : set = _set_leaf_fill  ## 1.0 = keine Lücke, kleiner = getrenntere Blätter

@export var regenerate: bool = false : set = _do_regenerate


func _set_leaf_count(v: int) -> void:
	leaf_count = maxi(3, v)
	_build()

func _set_rings(v: int) -> void:
	rings = maxi(2, v)
	_build()

func _set_base_radius(v: float) -> void:
	base_radius = v
	_build()

func _set_top_radius(v: float) -> void:
	top_radius = v
	_build()

func _set_height(v: float) -> void:
	crown_height = v
	_build()

func _set_curve(v: float) -> void:
	curve = v
	_build()

func _set_leaf_fill(v: float) -> void:
	leaf_fill = clampf(v, 0.1, 1.0)
	_build()

func _do_regenerate(_v: bool) -> void:
	_build()


func _ready() -> void:
	if mesh == null:
		_build()


func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Vertex-Grid pro Blatt aufbauen: [leaf][ring][side]
	var vert_grid: Array = []
	var vert_data: Array = []  # speichert {pos, uv, normal} in Reihenfolge

	for leaf in range(leaf_count):
		var ang_center: float = (float(leaf) + 0.5) / float(leaf_count) * TAU
		var half_ang: float = (leaf_fill / float(leaf_count)) * PI
		var leaf_rows: Array = []
		for r in range(rings + 1):
			var t: float = float(r) / float(rings)
			# Blatt-Wölbung: Parabel, die zur Mitte anschwillt (Blattform)
			var profile: float = sin(t * PI) * curve
			var radius: float = base_radius + (top_radius - base_radius) * t + profile
			var y: float = crown_height * t
			var row: Array = []
			for side in range(2):
				var a: float = ang_center + (half_ang if side == 1 else -half_ang)
				var pos := Vector3(cos(a) * radius, y, sin(a) * radius)
				var uv := Vector2(float(side), t)
				var nrm := Vector3(cos(a), 0.3, sin(a)).normalized()
				var idx: int = vert_data.size()
				vert_data.append({"pos": pos, "uv": uv, "normal": nrm})
				row.append(idx)
			leaf_rows.append(row)
		vert_grid.append(leaf_rows)

	# Dreiecke bilden: pro Blatt zwischen ring r und r+1 ein Quad
	for leaf in range(leaf_count):
		for r in range(rings):
			var a: int = vert_grid[leaf][r][0]
			var b: int = vert_grid[leaf][r][1]
			var c: int = vert_grid[leaf][r + 1][0]
			var d: int = vert_grid[leaf][r + 1][1]
			_add_tri(st, vert_data, a, c, b)
			_add_tri(st, vert_data, b, c, d)

	st.generate_tangents()
	mesh = st.commit()


func _add_tri(st: SurfaceTool, vert_data: Array, i0: int, i1: int, i2: int) -> void:
	for i in [i0, i1, i2]:
		var v: Dictionary = vert_data[i]
		st.set_uv(v["uv"])
		st.set_normal(v["normal"])
		st.add_vertex(v["pos"])
