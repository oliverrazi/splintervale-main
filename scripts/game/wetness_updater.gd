extends Node

const MAX_WATERFALLS := 3
var _waterfalls: Array = []
var _player: Node3D
var _update_timer: float = 0.0
const UPDATE_INTERVAL := 0.15  # 6.6× pro Sekunde reicht völlig

func register_waterfall(wf: Node3D, wetness_radius: float = 4.0) -> void:
	if not _has_entry(wf):
		_waterfalls.append({"node": wf, "radius": wetness_radius})

func unregister_waterfall(wf: Node3D) -> void:
	_waterfalls = _waterfalls.filter(func(e): return e.node != wf)

func _has_entry(wf: Node3D) -> bool:
	for e in _waterfalls:
		if e.node == wf: return true
	return false

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL: return
	_update_timer = 0.0
	_update_globals()

func _update_globals() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null: return
	
	_waterfalls = _waterfalls.filter(func(e): return is_instance_valid(e.node))
	
	var pp := _player.global_position
	_waterfalls.sort_custom(func(a, b):
		return a.node.global_position.distance_squared_to(pp) < \
			   b.node.global_position.distance_squared_to(pp)
	)
	
	var count: int = min(_waterfalls.size(), MAX_WATERFALLS)
	var inactive_pos := Vector3(0, -10000, 0)
	
	for i in MAX_WATERFALLS:
		var pos: Vector3
		var radius: float
		var height: float
		if i < count:
			var e = _waterfalls[i]
			pos = e.node.global_position
			radius = e.radius
			height = e.node.waterfall_height  # NEU – greift auf den @export zu
		else:
			pos = inactive_pos
			radius = 0.001
			height = 0.001
		RenderingServer.global_shader_parameter_set("waterfall_pos_" + str(i), pos)
		RenderingServer.global_shader_parameter_set("waterfall_radius_" + str(i), radius)
		RenderingServer.global_shader_parameter_set("waterfall_height_" + str(i), height)
	
	RenderingServer.global_shader_parameter_set("waterfall_count", count)
