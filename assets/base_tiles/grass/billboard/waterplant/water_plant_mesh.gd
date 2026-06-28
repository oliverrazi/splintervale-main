class_name WaterPlantMesh
extends RefCounted

## Erzeugt ein vertikal segmentiertes Quad als ArrayMesh.
## UV: x ∈ [0,1] horizontal, y ∈ [0,1] mit y=0 UNTEN (Fuß), y=1 OBEN (Spitze).
## Damit ist uv.y direkt das Krümmungsgewicht im Shader.

static func build(height: float, width: float, segments: int) -> ArrayMesh:
	segments = maxi(segments, 1)
	var rows := segments + 1

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var half_w := width * 0.5

	for r in range(rows):
		var t := float(r) / float(segments)   # 0 unten → 1 oben
		var y := t * height
		# linke + rechte Vertex-Spalte
		verts.push_back(Vector3(-half_w, y, 0.0))
		verts.push_back(Vector3( half_w, y, 0.0))
		# UV: y=0 unten. (Godot-UV hat y nach unten, daher invertiert speichern,
		# damit Sprite aufrecht steht: oberer Mesh-Rand = obere Texturzeile.)
		uvs.push_back(Vector2(0.0, 1.0 - t))
		uvs.push_back(Vector2(1.0, 1.0 - t))
		# Normalen nach +Z (Pflanze "schaut" nach vorne; fixe Ausrichtung)
		normals.push_back(Vector3(0, 0, 1))
		normals.push_back(Vector3(0, 0, 1))

	for s in range(segments):
		var bl := s * 2
		var br := s * 2 + 1
		var tl := (s + 1) * 2
		var tr := (s + 1) * 2 + 1
		# zwei Dreiecke, CCW von vorne (+Z)
		indices.push_back(bl); indices.push_back(br); indices.push_back(tr)
		indices.push_back(bl); indices.push_back(tr); indices.push_back(tl)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
