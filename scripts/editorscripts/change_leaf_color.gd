@tool
extends EditorScript

# Konfigurierbare Werte
const TARGET_SCENE := "res://assets/base_tiles/trees/pinetree5.tscn"
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
	if n is MeshInstance3D && n.name.contains("leaf"):
		changed += _change_mesh_instance_color(n)


	# Kinder rekursiv
	for c in n.get_children():
		_process_node(c, changed)


func _change_mesh_instance_color(mi: MeshInstance3D) -> int:
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
	
	mat.albedo_color = Color(0.0, 0.798, 1.983)
	modified = true
	return modified
