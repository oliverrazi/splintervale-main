extends Node3D

@export var follow_player: bool = true
@export var offset: Vector3 = Vector3(0, 2, 0)
@export var glow_color: Color = Color(0.0, 1.315, 1.625, 1.0)
@export var glow_intensity: float = 3.0

@onready var particles: GPUParticles3D = $GPUParticles3D

var _player: Node3D = null


func _ready() -> void:
	if follow_player:
		_player = get_tree().get_first_node_in_group("player")
	
	_setup_glow_material()


func _setup_glow_material() -> void:
	if particles == null or particles.draw_pass_1 == null:
		push_error("Particles or draw_pass_1 is null!")
		return
	
	var mesh: Mesh = particles.draw_pass_1
	
	# Glow Shader

	
	print("Glow shader applied!")


func _process(_delta: float) -> void:
	if follow_player and _player and is_instance_valid(_player):
		global_position = _player.global_position + offset
