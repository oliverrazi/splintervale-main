class_name WaterPlantRuntime
extends Node3D

## Laedt WaterPlantData und haengt pro Chunk eine MultiMeshInstance3D ein.
## Jeder Chunk hat seine eigene (kleine) AABB -> Godot cullt entfernte Chunks
## einzeln weg. Das Material wird von allen Chunks GETEILT (globale Welle).

@export var data: WaterPlantData
## Optionaler Pfad. Wird genutzt, um die Resource cache-frei neu zu laden
## (umgeht Godots Resource-Cache, der sonst veraltete Bake-Versionen haelt).
@export var data_path: String = "res://water_plants/baked_plants.tres"
@export var reload_fresh: bool = true
@export var cast_shadows: bool = false

var _instances: Array[MultiMeshInstance3D] = []

func _ready() -> void:
	# Frisch von der Platte laden, am Cache vorbei.
	if reload_fresh and not data_path.is_empty():
		var fresh := ResourceLoader.load(
			data_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if fresh is WaterPlantData:
			data = fresh

	if data == null or data.chunks.is_empty():
		push_warning("WaterPlantRuntime: keine Data/Chunks (data=%s, path=%s)" % [data, data_path])
		return

	var shadow_setting := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	# Pro Chunk eine MultiMeshInstance3D mit eigener AABB -> einzeln cullbar.
	for chunk in data.chunks:
		if chunk == null or chunk.multimesh == null:
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = chunk.multimesh
		mmi.material_override = data.material
		mmi.cast_shadow = shadow_setting
		# DIAGNOSE: stark vergroessert. Wenn das Flackern damit weg ist, war es
		# Culling an zu knappen Chunk-AABBs. Danach sauber auf Wellenauslenkung
		# dimensionieren (Wert wieder reduzieren).
		mmi.custom_aabb = chunk.aabb.grow(5.0)
		add_child(mmi)
		_instances.append(mmi)

func set_wave_params(speed: float, amplitude: float) -> void:
	# Geteiltes Material -> wirkt sofort auf ALLE Chunks.
	if data and data.material:
		data.material.set_shader_parameter("wave_speed", speed)
		data.material.set_shader_parameter("wave_amplitude", amplitude)
