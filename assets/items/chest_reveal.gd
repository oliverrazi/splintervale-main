extends Node3D
class_name ChestReveal

## Enthuellt eine in der Welt bereits platzierte Truhe mit GodRay-Effekt.

@export_group("Target")
@export var target_chest_path: NodePath

@export_group("Timing")
@export var god_ray_fade_in: float = 0.6
@export var pre_chest_reveal: float = 0.0
@export var god_ray_hold_after_chest: float = 0.4
@export var god_ray_fade_out: float = 1.0

@export_group("Light Flash")
@export var flash_peak_energy: float = 1.2
@export var flash_color: Color = Color(0.7, 0.9, 1.0)

@export_group("Floor Spot")
## Maximale Alpha des Boden-Spots. Niedriger = dezenter.
@export var floor_spot_alpha: float = 0.35

@export_group("Audio")
@export var reveal_sound: AudioStream
@export var sound_pitch_variation: float = 0.03

@onready var beam: MeshInstance3D = $GodRay/Beam
@onready var floor_spot: MeshInstance3D = $GodRay/Floor
@onready var light_flash: OmniLight3D = $LightFlash
@onready var audio: AudioStreamPlayer3D = $AudioPlayer

var _beam_material: ShaderMaterial
var _floor_material: StandardMaterial3D
var _target_chest: Node3D = null


func set_target_chest(chest: Node3D) -> void:
	_target_chest = chest


func play() -> void:
	if _target_chest == null and not target_chest_path.is_empty():
		_target_chest = get_node_or_null(target_chest_path) as Node3D
	
	var beam_base := beam.material_override as ShaderMaterial
	if beam_base:
		_beam_material = beam_base.duplicate() as ShaderMaterial
		beam.material_override = _beam_material
		_beam_material.set_shader_parameter("fade_in", 0.0)
	
	var floor_base := floor_spot.material_override as StandardMaterial3D
	if floor_base:
		_floor_material = floor_base.duplicate() as StandardMaterial3D
		floor_spot.material_override = _floor_material
		var col := _floor_material.albedo_color
		col.a = 0.0
		_floor_material.albedo_color = col
	
	if reveal_sound and audio:
		audio.stream = reveal_sound
		audio.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		audio.play()
	
	_tween_god_ray_in()


func _tween_god_ray_in() -> void:
	var tw := create_tween().set_parallel()
	
	if _beam_material:
		tw.tween_property(_beam_material, "shader_parameter/fade_in", 1.0, god_ray_fade_in) \
			.set_ease(Tween.EASE_OUT)
	
	if _floor_material:
		tw.tween_property(_floor_material, "albedo_color:a", floor_spot_alpha, god_ray_fade_in) \
			.set_ease(Tween.EASE_OUT)
	
	var until_chest := god_ray_fade_in + pre_chest_reveal
	get_tree().create_timer(until_chest).timeout.connect(_reveal_chest)


func _reveal_chest() -> void:
	if not is_inside_tree():
		return
	
	if _target_chest and is_instance_valid(_target_chest):
		if _target_chest.has_method("reveal_with_animation"):
			_target_chest.reveal_with_animation()
	
	if light_flash:
		light_flash.light_color = flash_color
		var flash_tw := create_tween()
		flash_tw.tween_property(light_flash, "light_energy", flash_peak_energy, 0.12) \
			.set_ease(Tween.EASE_OUT)
		flash_tw.tween_property(light_flash, "light_energy", 0.0, 0.5) \
			.set_ease(Tween.EASE_OUT)
	
	var fade_out_delay: float = 0.6 + god_ray_hold_after_chest
	get_tree().create_timer(fade_out_delay).timeout.connect(_fade_out_god_ray)


func _fade_out_god_ray() -> void:
	if not is_inside_tree():
		return
	
	var tw := create_tween().set_parallel()
	
	if _beam_material:
		tw.tween_property(_beam_material, "shader_parameter/fade_in", 0.0, god_ray_fade_out) \
			.set_ease(Tween.EASE_IN)
	
	if _floor_material:
		tw.tween_property(_floor_material, "albedo_color:a", 0.0, god_ray_fade_out) \
			.set_ease(Tween.EASE_IN)
	
	tw.chain().tween_callback(queue_free)
