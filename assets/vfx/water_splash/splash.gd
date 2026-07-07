class_name WaterSplash
extends Node3D

@export var foam_ring: MeshInstance3D
@export var spray: GPUParticles3D
@export var mist: GPUParticles3D
@export var crown_blobs: GPUParticles3D

var _lifetime: float = 0.6
var _time: float = 0.0
var _active: bool = false
var _foam_mat: ShaderMaterial

func _ready() -> void:
	_foam_mat = foam_ring.get_active_material(0) as ShaderMaterial
	set_active(false)

func play(world_pos: Vector3, intensity: float = 1.0, _direction: float = 1.0) -> void:
	global_position = world_pos
	_time = 0.0
	_active = true
	if _foam_mat:
		_foam_mat.set_shader_parameter("intensity", intensity)
	set_active(true)
	if spray:
		spray.restart()
		spray.emitting = true
	if mist:
		mist.restart()
		mist.emitting = true
	if crown_blobs:
		crown_blobs.restart()
		crown_blobs.emitting = true

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _foam_mat:
		_foam_mat.set_shader_parameter("splash_time", _time)
	if _time >= _lifetime:
		_active = false
		set_active(false)

func set_active(value: bool) -> void:
	visible = value
	foam_ring.visible = value
	set_process(value)
