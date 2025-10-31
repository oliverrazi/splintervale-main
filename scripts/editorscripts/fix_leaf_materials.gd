@tool
extends EditorScript

# Konfigurierbare Werte
const TARGET_SCENE := "res://assets/base_tiles/pinetree.tscn"
const THRESHOLD := 0.4

func _run() -> void:
	var packed: PackedScene = ResourceLoader.load(TARGET_SCENE)
	if packed == null:
		push_error("Scene not found: %s" % TARGET_SCENE)
		return

	var root: Node = packed.instantiate()
	if root == null:
		push_error("Could not instantiate scene.")
		return

	var changed := 0

	# Alle Nodes der Szene durchlaufen
	_process_node(root, changed)

	# Änderungen in die .tscn zurückschreiben
	var ok := packed.pack(root)
	if ok != OK:
		push_error("Failed to pack scene (error code %s)." % str(ok))
		return

	ok = ResourceSaver.save(packed, TARGET_SCENE)
	if ok != OK:
		push_error("Failed to save scene (error code %s)." % str(ok))
		return

	print("✅ Done. Materials updated:", changed)


func _process_node(n: Node, changed: int) -> void:
	# MeshInstance3D (Blätter/Äste) behandeln
	if n is MeshInstance3D:
		changed += _fix_mesh_instance_materials(n)

	# Optional: Material-Override auf GeometryInstance3D beachten
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		if gi.material_override and gi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = gi.material_override
			if _fix_material_in_place(mat):
				gi.material_override = mat
				changed += 1

	# Kinder rekursiv
	for c in n.get_children():
		_process_node(c, changed)


func _fix_mesh_instance_materials(mi: MeshInstance3D) -> int:
	var count := 0
	var mesh := mi.mesh
	if mesh == null:
		return 0

	# 1) Per-Surface Overrides prüfen und ggf. setzen
	var surfaces := mesh.get_surface_count()
	for i in range(surfaces):
		var mat: Material = mi.get_surface_override_material(i)
		if mat == null:
			# Fallback: Material aus dem Mesh lesen
			mat = mesh.surface_get_material(i)

		if mat == null:
			continue

		# Nur StandardMaterial3D bearbeiten
		if mat is StandardMaterial3D:
			var new_mat: StandardMaterial3D = mat

			# Externe/partagierte Ressourcen nicht global verändern:
			# Duplizieren und als Override setzen, damit nur tree2.tscn betroffen ist.
			if mat.resource_path != "":
				new_mat = mat.duplicate() as StandardMaterial3D
				new_mat.resource_path = ""  # als Subresource/Override in der Szene

			var modified := _fix_material_in_place(new_mat)
			if modified:
				mi.set_surface_override_material(i, new_mat)
				count += 1

	return count


func _fix_material_in_place(mat: StandardMaterial3D) -> bool:
	var modified := false
	# Nur umstellen, wenn tatsächlich Alpha Blend aktiv ist
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		print("GO")
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		modified = true

	return modified
