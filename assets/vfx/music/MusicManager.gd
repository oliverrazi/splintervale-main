# MusicManager.gd
extends Node

var _current_player: AudioStreamPlayer
var _next_player: AudioStreamPlayer
var _tween: Tween
var _active_zones: Array[MusicZone] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_player = AudioStreamPlayer.new()
	_next_player = AudioStreamPlayer.new()
	_current_player.bus = "Music"
	_next_player.bus = "Music"
	add_child(_current_player)
	add_child(_next_player)

func enter_zone(zone: MusicZone) -> void:
	if zone not in _active_zones:
		_active_zones.append(zone)
	_update_music()

func exit_zone(zone: MusicZone) -> void:
	_active_zones.erase(zone)
	_update_music()

func _update_music() -> void:
	if _active_zones.is_empty():
		_fade_out()
		return
	
	# Zone mit höchster Priorität gewinnt
	_active_zones.sort_custom(func(a, b): return a.zone_priority  > b.zone_priority )
	var target_track := _active_zones[0].music_track
	var fade_time := _active_zones[0].crossfade_duration
	
	if _current_player.stream != target_track:
		_crossfade_to(target_track, fade_time)

func _crossfade_to(track: AudioStream, fade_time: float) -> void:
	if _tween:
		_tween.kill()
	
	_next_player.stream = track
	_next_player.volume_db = -80.0
	_next_player.play()
	
	_tween = create_tween().set_parallel()
	_tween.tween_property(_current_player, "volume_db", -80.0, fade_time)
	_tween.tween_property(_next_player, "volume_db", 0.0, 0.0)
	_tween.chain().tween_callback(_swap_players)

func _fade_out(fade_time: float = 2.0) -> void:
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.tween_property(_current_player, "volume_db", -80.0, fade_time)
	_tween.tween_callback(func():
		_current_player.stop()
		_current_player.stream = null
	)

func _swap_players() -> void:
	_current_player.stop()
	var temp := _current_player
	_current_player = _next_player
	_next_player = temp
