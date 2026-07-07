## LayeredPixelSprite3D
##
## Paper-Doll Sprite System für HD-2D.
## Verwaltet mehrere SmoothPixelSprite3D als synchronisierte Layer.
## Alle Layer teilen dasselbe Grid-Layout (hframes/vframes) und werden
## bei frame, flip_h, modulate etc. synchron gehalten.
##
## WICHTIG: Diesen Node als Node3D in der Scene erstellen (NICHT als
## SmoothPixelSprite3D/MeshInstance3D). Er erstellt seine Children selbst.
## Das alte SmoothPixelSprite3D/MeshInstance3D unter "charactersprite" ENTFERNEN,
## stattdessen dieses Script auf einen leeren Node3D legen.
##
## Setup im Scene-Tree:
##   Player (CharacterBody3D)
##     └─ charactersprite (Node3D + LayeredPixelSprite3D.gd)
##         └─ Layer_base      (automatisch erstellt)
##         └─ Layer_weapon     (automatisch erstellt)
##         └─ Layer_vector_anchor (automatisch erstellt)

@tool
class_name LayeredPixelSprite3D
extends Node3D

# ─── Shared Properties (sync to all layers) ───

@export var hframes: int = 1 : set = _set_hframes
@export var vframes: int = 1 : set = _set_vframes
@export var frame: int = 0 : set = _set_frame
@export var flip_h: bool = false : set = _set_flip_h
@export var pixel_size: float = 0.01 : set = _set_pixel_size

## Farbmodulation inkl. Alpha — wird auf ALLE Layer gleichzeitig angewendet.
## Für per-Layer Modulation: get_layer("weapon").modulate = ...
@export var modulate: Color = Color.WHITE : set = _set_modulate

## Render-Layer (VisualInstance3D.layers) für ALLE erzeugten Sprite-Layer.
## Für den Player auf NUR Layer 2 stellen, damit Lichter ihn per
## light_cull_mask gezielt aus-/einschließen können (HD-2D Licht-Trennung).
@export_flags_3d_render var render_layers: int = 1 : set = _set_render_layers

@export var billboard_mode: SmoothPixelSprite3D.BillboardMode = SmoothPixelSprite3D.BillboardMode.FULL : set = _set_billboard_mode
@export_range(0.0, 0.5, 0.01) var tilt_amount: float = 0.15 : set = _set_tilt_amount
@export var filter_algorithm: SmoothPixelSprite3D.FilterAlgorithm = SmoothPixelSprite3D.FilterAlgorithm.SMOOTHSTEP : set = _set_filter_algorithm
@export_range(0.3, 3.0, 0.1) var aa_sharpness: float = 1.2 : set = _set_aa_sharpness
@export_range(0.0, 1.0, 0.1) var frame_bleed_guard: float = 0.5 : set = _set_frame_bleed_guard

@export_group("Base Layer")
## Die Basis-Textur (Character-Body ohne Waffen/Items).
@export var base_texture: Texture2D

# ─── Internals ───

var _layers: Dictionary = {}           # String -> SmoothPixelSprite3D
var _layer_priorities: Dictionary = {}  # String -> int


func _ready() -> void:
	if base_texture:
		set_layer("base", base_texture, 0)


# ─── Layer Management ───

func set_layer(layer_key: String, tex: Texture2D, priority: int = -1, depth_bias: float = -1.0) -> void:
	if tex == null:
		remove_layer(layer_key)
		return

	if priority < 0:
		priority = _get_default_priority(layer_key)

	if depth_bias < 0.0:
		depth_bias = _get_default_depth_bias(layer_key)

	# Layer existiert bereits → nur Textur tauschen
	if _layers.has(layer_key):
		_layers[layer_key].texture = tex
		_layers[layer_key].depth_bias = depth_bias
		if _layer_priorities.get(layer_key, -1) != priority:
			_layer_priorities[layer_key] = priority
			_apply_render_priority(_layers[layer_key], priority)
		return

	# Neuen Layer erstellen
	var sprite := SmoothPixelSprite3D.new()
	sprite.name = "Layer_" + layer_key
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.layers = render_layers


	# Shared Properties setzen BEVOR add_child
	sprite.hframes = hframes
	sprite.vframes = vframes
	sprite.pixel_size = pixel_size
	sprite.billboard_mode = billboard_mode
	sprite.tilt_amount = tilt_amount
	sprite.filter_algorithm = filter_algorithm
	sprite.aa_sharpness = aa_sharpness
	sprite.frame_bleed_guard = frame_bleed_guard
	sprite.depth_bias = depth_bias
	sprite.texture = tex

	# add_child triggert _ready() → Material wird erstellt
	add_child(sprite)

	# Frame, flip, modulate NACH add_child (Material existiert jetzt)
	sprite.frame = frame
	sprite.flip_h = flip_h
	sprite.modulate = modulate
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_layers[layer_key] = sprite
	_layer_priorities[layer_key] = priority
	_apply_render_priority(sprite, priority)

func _get_default_depth_bias(layer_key: String) -> float:
	match layer_key:
		"weapon", "vector_anchor":
			return 0.3  # Startwert — bei Bedarf tunen
		_:
			return 0.0

func swap_layer(layer_key: String, tex: Texture2D) -> void:
	set_layer(layer_key, tex)


func remove_layer(layer_key: String) -> void:
	if not _layers.has(layer_key):
		return
	var sprite: SmoothPixelSprite3D = _layers[layer_key]
	if is_instance_valid(sprite):
		sprite.queue_free()
	_layers.erase(layer_key)
	_layer_priorities.erase(layer_key)


func has_layer(layer_key: String) -> bool:
	return _layers.has(layer_key)


func get_layer(layer_key: String) -> SmoothPixelSprite3D:
	return _layers.get(layer_key)


func get_all_layer_keys() -> Array:
	return _layers.keys()

func set_layer_visible(layer_key: String, is_visible: bool) -> void:
	if _layers.has(layer_key):
		_layers[layer_key].visible = is_visible

## Alle Layer außer "base" entfernen.
func clear_overlays() -> void:
	var keys_to_remove: Array = []
	for key in _layers.keys():
		if key != "base":
			keys_to_remove.append(key)
	for key in keys_to_remove:
		remove_layer(key)


# ─── Render Priority ───

func _apply_render_priority(sprite: SmoothPixelSprite3D, priority: int) -> void:
	if sprite.material_override:
		sprite.material_override.render_priority = priority
	else:
		sprite.ready.connect(func():
			if sprite.material_override:
				sprite.material_override.render_priority = priority
		, CONNECT_ONE_SHOT)


func _get_default_priority(layer_key: String) -> int:
	match layer_key:
		"base":
			return 0
		"body", "body_armor", "armor":
			return 1
		"weapon", "vector_anchor":
			return 2
		"accessory", "shield", "cloak":
			return 3
		"vfx", "aura", "effect":
			return 4
		_:
			return 5


# ─── Sync Setters ───

func _set_hframes(value: int) -> void:
	hframes = max(1, value)
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.hframes = hframes

func _set_vframes(value: int) -> void:
	vframes = max(1, value)
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.vframes = vframes

func _set_frame(value: int) -> void:
	frame = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.frame = value

func _set_flip_h(value: bool) -> void:
	flip_h = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.flip_h = value

func _set_pixel_size(value: float) -> void:
	pixel_size = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.pixel_size = value

func _set_modulate(value: Color) -> void:
	modulate = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.modulate = value

func _set_render_layers(value: int) -> void:
	render_layers = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.layers = render_layers

func _set_billboard_mode(value: SmoothPixelSprite3D.BillboardMode) -> void:
	billboard_mode = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.billboard_mode = value

func _set_tilt_amount(value: float) -> void:
	tilt_amount = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.tilt_amount = value

func _set_filter_algorithm(value: SmoothPixelSprite3D.FilterAlgorithm) -> void:
	filter_algorithm = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.filter_algorithm = value

func _set_aa_sharpness(value: float) -> void:
	aa_sharpness = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.aa_sharpness = value

func _set_frame_bleed_guard(value: float) -> void:
	frame_bleed_guard = value
	for sprite: SmoothPixelSprite3D in _layers.values():
		sprite.frame_bleed_guard = value
