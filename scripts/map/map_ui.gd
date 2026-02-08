extends Control
class_name MapUI

## Map UI für das Pause-Menü
## Pergament-Look mit Fog of War

# === MAP SETTINGS ===
@export_group("Map Settings")
@export var map_texture_path: String = "res://assets/map/world_map.png"

# Welt-Grenzen (berechnet aus MapCaptureCamera: center ± size/2)
# Map Center: X=-25, Z=150 | Map Size: 220x220
@export var world_x_min: float = -135.0  # -25 - 110
@export var world_x_max: float = 85.0    # -25 + 110
@export var world_z_min: float = 40.0    # 150 - 110
@export var world_z_max: float = 260.0   # 150 + 110

@export_group("Visual")
@export var margin: float = 20.0
@export var border_width: float = 4.0
@export var border_color: Color = Color(0.35, 0.25, 0.15)

@export_group("Player Marker")
@export var player_icon_path: String = "res://menu/assets/icons/player_icon.png"  # Leer = Standard-Kreis
@export var player_marker_size: float = 14.0
@export var player_marker_color: Color = Color(0.85, 0.15, 0.15)
@export var player_marker_outline: Color = Color(0.2, 0.1, 0.05)

@export_group("Fog of War")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.472, 0.484, 0.475, 1.0)
@export var reveal_radius: float = 10.0

# === NODES ===
var _bg_panel: Panel
var _map_margin: MarginContainer
var _map_container: Control
var _map_texture_rect: TextureRect
var _fog_rect: ColorRect
var _player_marker: Control
var _player_icon_texture: Texture2D = null

# === FOG DATA ===
var _fog_image: Image
var _fog_texture: ImageTexture
const FOG_RESOLUTION: int = 256


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_player_icon()
	_setup_ui()
	_load_map_texture()
	_setup_fog_of_war()
	
	print("MapUI Ready - World bounds: X[", world_x_min, " to ", world_x_max, "] Z[", world_z_min, " to ", world_z_max, "]")


func _load_player_icon() -> void:
	if player_icon_path != "" and ResourceLoader.exists(player_icon_path):
		_player_icon_texture = load(player_icon_path)
		print("MapUI: Loaded player icon from ", player_icon_path)


func _setup_ui() -> void:
	# === Pergament Hintergrund mit Shader ===
	_bg_panel = Panel.new()
	_bg_panel.name = "PergamentBG"
	_bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_panel)
	
	# Pergament Shader anwenden
	_apply_pergament_shader(_bg_panel)
	
	# === Margin Container ===
	_map_margin = MarginContainer.new()
	_map_margin.name = "MapMargin"
	_map_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_margin.add_theme_constant_override("margin_left", int(margin))
	_map_margin.add_theme_constant_override("margin_right", int(margin))
	_map_margin.add_theme_constant_override("margin_top", int(margin))
	_map_margin.add_theme_constant_override("margin_bottom", int(margin))
	add_child(_map_margin)
	
	# === Map Container mit Clip ===
	_map_container = Control.new()
	_map_container.name = "MapContainer"
	_map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.clip_contents = true
	_map_margin.add_child(_map_container)
	
	# === Rahmen ===
	var border := ReferenceRect.new()
	border.name = "Border"
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.border_color = border_color
	border.border_width = border_width
	border.editor_only = false
	_map_container.add_child(border)
	
	# === Karten-Textur ===
	_map_texture_rect = TextureRect.new()
	_map_texture_rect.name = "MapTexture"
	_map_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_container.add_child(_map_texture_rect)
	
	# === Fog of War Overlay ===
	_fog_rect = ColorRect.new()
	_fog_rect.name = "FogOverlay"
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.add_child(_fog_rect)
	
	# === Spieler-Marker ===
	_player_marker = Control.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.custom_minimum_size = Vector2(player_marker_size, player_marker_size*1.8)
	_player_marker.size = Vector2(player_marker_size, player_marker_size*1.8)
	_player_marker.z_index = 10
	_player_marker.draw.connect(_on_draw_player_marker)
	_map_container.add_child(_player_marker)


func _apply_pergament_shader(panel: Panel) -> void:
	var shader_code := """
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.82, 0.72, 0.55, 1.0);
uniform vec4 dark_color : source_color = vec4(0.65, 0.55, 0.38, 1.0);
uniform vec4 stain_color : source_color = vec4(0.7, 0.6, 0.4, 1.0);
uniform float noise_scale : hint_range(1.0, 20.0) = 8.0;
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.3;
uniform float stain_intensity : hint_range(0.0, 1.0) = 0.15;

// Simplex-like noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	
	// Basis-Noise für Pergament-Textur
	float n = fbm(uv * noise_scale);
	float n2 = fbm(uv * noise_scale * 2.0 + vec2(5.0, 3.0));
	
	// Farbe mischen
	vec3 color = mix(base_color.rgb, dark_color.rgb, n * 0.4);
	
	// Flecken hinzufügen
	float stains = fbm(uv * noise_scale * 0.5 + vec2(10.0, 20.0));
	stains = smoothstep(0.4, 0.6, stains);
	color = mix(color, stain_color.rgb, stains * stain_intensity);
	
	// Feine Körnung
	float grain = hash(uv * 500.0) * 0.08;
	color += grain - 0.04;
	
	// Kanten abdunkeln (Vignette)
	vec2 edge_dist = abs(uv - 0.5) * 2.0;
	float edge = max(edge_dist.x, edge_dist.y);
	edge = smoothstep(0.7, 1.0, edge);
	color = mix(color, dark_color.rgb * 0.7, edge * edge_darkness);
	
	// Leichte Falten/Linien
	float lines = noise(uv * vec2(noise_scale * 3.0, noise_scale * 0.5));
	lines = smoothstep(0.48, 0.52, lines) * 0.1;
	color -= lines;
	
	COLOR = vec4(color, 1.0);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	
	var material := ShaderMaterial.new()
	material.shader = shader
	
	# StyleBox für Panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE  # Wird vom Shader überschrieben
	panel.add_theme_stylebox_override("panel", style)
	
	panel.material = material


func _load_map_texture() -> void:
	if ResourceLoader.exists(map_texture_path):
		var tex = load(map_texture_path)
		if tex:
			_map_texture_rect.texture = tex
			print("MapUI: Loaded map texture")
			return
	
	push_warning("MapUI: Map texture not found at ", map_texture_path)
	_create_placeholder()


func _create_placeholder() -> void:
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.45, 0.35))
	_map_texture_rect.texture = ImageTexture.create_from_image(img)


func _setup_fog_of_war() -> void:
	if not fog_enabled:
		_fog_rect.visible = false
		return
	
	# Fog Image erstellen
	_fog_image = Image.create(FOG_RESOLUTION, FOG_RESOLUTION, false, Image.FORMAT_L8)
	_fog_image.fill(Color.BLACK)
	
	_load_fog_data()
	
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	
	# Fog Shader
	var shader_code := """
shader_type canvas_item;

uniform sampler2D fog_texture : filter_linear;
uniform vec4 fog_color : source_color = vec4(0.25, 0.2, 0.12, 0.93);
uniform float edge_softness : hint_range(0.01, 0.3) = 0.12;

void fragment() {
	float revealed = texture(fog_texture, UV).r;
	float alpha = 1.0 - smoothstep(0.0, edge_softness, revealed);
	COLOR = vec4(fog_color.rgb, fog_color.a * alpha);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("fog_color", fog_color)
	material.set_shader_parameter("fog_texture", _fog_texture)
	material.set_shader_parameter("edge_softness", 0.12)
	
	_fog_rect.material = material


func _on_draw_player_marker() -> void:
	var center := _player_marker.size / 2.0
	
	if _player_icon_texture:
		# Custom Icon zeichnen
		var icon_size := _player_marker.size
		var icon_rect := Rect2(Vector2.ZERO, icon_size)
		_player_marker.draw_texture_rect(_player_icon_texture, icon_rect, false)
	else:
		# Standard: Roter Kreis mit Outline
		var r :float = min(_player_marker.size.x, _player_marker.size.y) / 2.0 - 1.0
		
		# Schatten
		_player_marker.draw_circle(center + Vector2(1, 1), r, Color(0, 0, 0, 0.3))
		
		# Outline
		_player_marker.draw_circle(center, r, player_marker_outline)
		
		# Innerer Kreis
		_player_marker.draw_circle(center, r * 0.7, player_marker_color)


func _process(_delta: float) -> void:
	if not visible:
		return
	
	_update_player_marker()
	_update_fog()


func _update_player_marker() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_player_marker.visible = false
		return
	
	_player_marker.visible = true
	
	var world_pos: Vector3 = player.global_position
	var map_pos := _world_to_map_normalized(world_pos)
	
	# Position auf Container-Größe mappen
	var container_size := _map_container.size
	var marker_pos := Vector2(
		map_pos.x * container_size.x,
		map_pos.y * container_size.y
	)
	
	_player_marker.position = marker_pos - _player_marker.size / 2.0
	_player_marker.queue_redraw()


func _world_to_map_normalized(world_pos: Vector3) -> Vector2:
	# X-Achse: Links = niedrige X, Rechts = hohe X
	var norm_x := (world_pos.x - world_x_min) / (world_x_max - world_x_min)
	
	# Z-Achse: Die Karte wurde mit der Kamera von Süden (niedriges Z) nach Norden (hohes Z) aufgenommen
	# Oben auf dem Bild = Norden = hohes Z
	# Unten auf dem Bild = Süden = niedriges Z
	# Screen Y ist invertiert (0 = oben), also:
	var norm_y := 1.0 - (world_pos.z - world_z_min) / (world_z_max - world_z_min)
	
	return Vector2(clamp(norm_x, 0.0, 1.0), clamp(norm_y, 0.0, 1.0))


func _update_fog() -> void:
	if not fog_enabled or _fog_image == null:
		return
	
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	
	_reveal_fog_at(player.global_position)


func _reveal_fog_at(world_pos: Vector3) -> void:
	var map_pos := _world_to_map_normalized(world_pos)
	var center_x := int(map_pos.x * FOG_RESOLUTION)
	var center_y := int(map_pos.y * FOG_RESOLUTION)
	
	# Radius berechnen
	var world_size :float = max(world_x_max - world_x_min, world_z_max - world_z_min)
	var base_r := (reveal_radius / world_size) * FOG_RESOLUTION
	base_r = max(base_r, 5.0)
	
	var y_stretch := 2.4
	var rx := base_r
	var ry := base_r * y_stretch

	var changed := false

	# Bounding-Box der Ellipse
	var ix := int(ceil(rx))
	var iy := int(ceil(ry))

	for dy in range(-iy, iy + 1):
		for dx in range(-ix, ix + 1):
			# Ellipsen-Innen-Test
			var nx := dx / rx
			var ny := dy / ry
			var d2 := nx * nx + ny * ny
			if d2 <= 1.0:
				var px := center_x + dx
				var py := center_y + dy

				if px >= 0 and px < FOG_RESOLUTION and py >= 0 and py < FOG_RESOLUTION:
					var current := _fog_image.get_pixel(px, py)
					if current.r < 0.99:
						# weicher Rand: "edge" anhand normalisierter Distanz
						var edge := 1.0 - sqrt(d2)   # sqrt(d2) ist 0..1
						var new_val: float = max(current.r, edge)
						_fog_image.set_pixel(px, py, Color(new_val, new_val, new_val))
						changed = true
	
	if changed:
		_fog_texture.update(_fog_image)


# === FOG SAVE/LOAD ===

const FOG_SAVE_PATH := "user://fog_data.png"


func _load_fog_data() -> void:
	if FileAccess.file_exists(FOG_SAVE_PATH):
		var loaded := Image.load_from_file(FOG_SAVE_PATH)
		if loaded:
			if loaded.get_width() != FOG_RESOLUTION:
				loaded.resize(FOG_RESOLUTION, FOG_RESOLUTION)
			_fog_image = loaded
			print("MapUI: Loaded fog data")


func save_fog_data() -> void:
	if _fog_image:
		_fog_image.save_png(FOG_SAVE_PATH)
		print("MapUI: Saved fog data")


func reset_fog() -> void:
	if _fog_image:
		_fog_image.fill(Color.BLACK)
		_fog_texture.update(_fog_image)
	
	if FileAccess.file_exists(FOG_SAVE_PATH):
		DirAccess.remove_absolute(FOG_SAVE_PATH)


func reveal_all() -> void:
	if _fog_image:
		_fog_image.fill(Color.WHITE)
		_fog_texture.update(_fog_image)
