extends Node

const POOL_SIZE := 16

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []

func _ready() -> void:
	# Pool beim Start befüllen – nicht zur Laufzeit
	for i in POOL_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		add_child(p3)
		_pool_3d.append(p3)
		
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool_2d.append(p2)

## Spielt einen 3D-Sound sofort ab (kein neuer Node, kein add_child)
func play_3d(stream: AudioStream, world_pos: Vector3,
			 volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player := _get_free_3d()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.global_position = world_pos
	player.play()

## Spielt einen 2D/UI-Sound sofort ab
func play_2d(stream: AudioStream,
			 volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player := _get_free_2d()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

func _get_free_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	# Alle besetzt → ältesten überschreiben
	var oldest := _pool_3d[0]
	_pool_3d.remove_at(0)
	_pool_3d.append(oldest)
	return oldest

func _get_free_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	var oldest := _pool_2d[0]
	_pool_2d.remove_at(0)
	_pool_2d.append(oldest)
	return oldest
