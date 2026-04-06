# hd2d_camera_system.gd
# Zwei-Pass System: 3D Welt + Orthographische Sprites
extends Node3D
class_name HD2DCameraSystem

@export var main_camera: Camera3D
@export var follow_target: Node3D

# Sprite-Layer wird orthographisch gerendert
var _sprite_viewport: SubViewport
var _sprite_camera: Camera3D
var _sprite_container: Node3D


func _ready() -> void:
	_setup_sprite_layer()


func _setup_sprite_layer() -> void:
	# SubViewport für Sprites
	_sprite_viewport = SubViewport.new()
	_sprite_viewport.size = get_viewport().size
	_sprite_viewport.transparent_bg = true
	_sprite_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sprite_viewport)
	
	# Orthographische Kamera für Sprites
	_sprite_camera = Camera3D.new()
	_sprite_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_sprite_camera.size = 10.0  # Anpassen je nach Spielgröße
	_sprite_viewport.add_child(_sprite_camera)
	
	# Container für alle HD-2D Sprites
	_sprite_container = Node3D.new()
	_sprite_container.name = "SpriteContainer"
	_sprite_viewport.add_child(_sprite_container)


func _process(_delta: float) -> void:
	if main_camera and _sprite_camera:
		# Sprite-Kamera folgt der Hauptkamera
		_sprite_camera.global_transform = main_camera.global_transform


func register_sprite(sprite: Node3D) -> void:
	# Sprite in den orthographischen Layer verschieben
	if sprite.get_parent():
		sprite.get_parent().remove_child(sprite)
	_sprite_container.add_child(sprite)
