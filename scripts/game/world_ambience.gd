extends Node3D

@export var sparks_scene: PackedScene
@export var dust_scene: PackedScene
@export var enable_sparks: bool = true
@export var enable_dust: bool = true

var _sparks_instance: Node3D = null
var _dust_instance: Node3D = null
var _player: Node3D = null


func _ready() -> void:
	call_deferred("_setup_ambience")


func _setup_ambience() -> void:
	_player = get_tree().get_first_node_in_group("player")
	
	if enable_sparks and sparks_scene:
		_sparks_instance = sparks_scene.instantiate()
		add_child(_sparks_instance)
	
	if enable_dust and dust_scene:
		_dust_instance = dust_scene.instantiate()
		add_child(_dust_instance)


func _process(_delta: float) -> void:
	if _player and is_instance_valid(_player):
		if _sparks_instance:
			_sparks_instance.global_position = _player.global_position + Vector3(0, 1, 0)
		if _dust_instance:
			_dust_instance.global_position = _player.global_position + Vector3(0, 2, 0)
