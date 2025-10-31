extends MeshInstance3D

@export var atlas_texture: Texture2D = preload("res://assets/base_tiles/dirt-block.png")
@export var cols := 3
@export var rows := 2

func _ready() -> void:
	mesh = _build_cube_with_atlas()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = atlas_texture
	# Optional: schärfer/sauberer
	# mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	# Helfer: UV-Rechteck aus Atlas-Zelle
func cell_rect(cx:int, cy:int) -> Dictionary:
	var u0 := float(cx) / float(cols)
	var v0 := float(cy) / float(rows)
	var u1 := float(cx + 1) / float(cols)
	var v1 := float(cy + 1) / float(rows)
	return { "u0": u0, "v0": v0, "u1": u1, "v1": v1 }

	# Helfer: eine Face (2 Dreiecke) schreiben
func add_face(st:SurfaceTool, v00:Vector3, v10:Vector3, v11:Vector3, v01:Vector3, n:Vector3, r:Dictionary) -> void:
	# Tri 1: v00, v10, v11
	st.set_normal(n)
	st.set_uv(Vector2(r.u0, r.v1)) ; st.add_vertex(v00)
	st.set_uv(Vector2(r.u1, r.v1)) ; st.add_vertex(v10)
	st.set_uv(Vector2(r.u1, r.v0)) ; st.add_vertex(v11)
	# Tri 2: v00, v11, v01
	st.set_normal(n)
	st.set_uv(Vector2(r.u0, r.v1)) ; st.add_vertex(v00)
	st.set_uv(Vector2(r.u1, r.v0)) ; st.add_vertex(v11)
	st.set_uv(Vector2(r.u0, r.v0)) ; st.add_vertex(v01)

func _build_cube_with_atlas() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var s := 0.5 # Halbgröße (Würfelkante = 1.0)



	# Atlas-Zuordnung pro Seite (frei veränderbar):
	# (+X, -X, +Y, -Y, +Z, -Z) -> Zelle (cx, cy)
	var face_cells = {
		"xp": Vector2i(2, 0), # +X
		"xn": Vector2i(0, 0), # -X
		"yp": Vector2i(1, 0), # +Y (Top)
		"yn": Vector2i(1, 1), # -Y (Bottom)
		"zp": Vector2i(0, 1), # +Z (Front)
		"zn": Vector2i(2, 1), # -Z (Back)
	}

	# +X
	add_face(
		st,
		Vector3( s,-s,-s), Vector3( s,-s, s), Vector3( s, s, s), Vector3( s, s,-s),
		Vector3(1,0,0),
		cell_rect(face_cells["xp"].x, face_cells["xp"].y)
	)
	# -X
	add_face(
		st,
		Vector3(-s,-s, s), Vector3(-s,-s,-s), Vector3(-s, s,-s), Vector3(-s, s, s),
		Vector3(-1,0,0),
		cell_rect(face_cells["xn"].x, face_cells["xn"].y)
	)
	# +Y (Top)
	add_face(
		st,
		Vector3(-s, s,-s), Vector3( s, s,-s), Vector3( s, s, s), Vector3(-s, s, s),
		Vector3(0,1,0),
		cell_rect(face_cells["yp"].x, face_cells["yp"].y)
	)
	# -Y (Bottom)
	add_face(
		st,
		Vector3(-s,-s, s), Vector3( s,-s, s), Vector3( s,-s,-s), Vector3(-s,-s,-s),
		Vector3(0,-1,0),
		cell_rect(face_cells["yn"].x, face_cells["yn"].y)
	)
	# +Z (Front)
	add_face(
		st,
		Vector3(-s,-s, s), Vector3( s,-s, s), Vector3( s, s, s), Vector3(-s, s, s),
		Vector3(0,0,1),
		cell_rect(face_cells["zp"].x, face_cells["zp"].y)
	)
	# -Z (Back)
	add_face(
		st,
		Vector3( s,-s,-s), Vector3(-s,-s,-s), Vector3(-s, s,-s), Vector3( s, s,-s),
		Vector3(0,0,-1),
		cell_rect(face_cells["zn"].x, face_cells["zn"].y)
	)

	var arr_mesh := st.commit()
	return arr_mesh
