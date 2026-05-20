extends Node3D

@export var radius: float = 1.1
@export var length: float = 2.4
@export var segments: int = 36
@export var duration: float = 0.7
@export var tint: Color = Color(1, 1, 1, 1)
@export var strength: float = 0.3        # bewusst niedrig = transparent
@export var wave_rings: int = 2
@export var ring_soft: float = 0.45
@export var noise_scale: float = 14.0
@export var noise_amount: float = 0.6

const CONE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.3;
uniform float wave_rings : hint_range(0.0, 6.0) = 2.0;
uniform float ring_soft : hint_range(0.05, 0.6) = 0.45;
uniform float noise_scale : hint_range(2.0, 40.0) = 14.0;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.6;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float v = UV.y;  // 0 = Spitze (am Oger), 1 = Mündung (zur Kamera)
	float wave = 0.5 + 0.5 * sin((v - progress) * wave_rings * 6.2831853);
	wave = smoothstep(0.5 - ring_soft, 0.5 + ring_soft, wave);
	float reach = 1.0 - smoothstep(progress, progress + 0.30, v);
	float inner_soft = smoothstep(0.0, 0.14, v);
	float outer_soft = 1.0 - smoothstep(0.82, 1.0, v);
	float life = smoothstep(0.0, 0.14, progress) * (1.0 - smoothstep(0.5, 1.0, progress));
	float n = vnoise(vec2(UV.x * noise_scale, v * noise_scale - progress * 4.0));
	n = mix(1.0, n, noise_amount);
	float a = strength * wave * reach * inner_soft * outer_soft * life * n;
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * tint.a;
	if (ALPHA < 0.003) discard;
}
"""

func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _build_cone()
	var sh := Shader.new()
	sh.code = CONE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 120
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("wave_rings", float(wave_rings))
	mat.set_shader_parameter("ring_soft", ring_soft)
	mat.set_shader_parameter("noise_scale", noise_scale)
	mat.set_shader_parameter("noise_amount", noise_amount)
	mi.material_override = mat
	add_child(mi)
	create_tween().tween_method(
		func(p): mat.set_shader_parameter("progress", p), 0.0, 1.0, duration)

func _build_cone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3.ZERO
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, -length)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, -length)
		st.set_uv(Vector2(float(i) / float(segments), 0.0));       st.add_vertex(apex)
		st.set_uv(Vector2(float(i) / float(segments), 1.0));       st.add_vertex(p0)
		st.set_uv(Vector2(float(i + 1) / float(segments), 1.0));   st.add_vertex(p1)
	st.generate_normals()
	return st.commit()
