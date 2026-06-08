shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

// === Atlas ===
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform int hframes = 10;
uniform int vframes = 10;
uniform int frame = 0;
uniform bool flip_h = false;

// === Dissolve ===
uniform sampler2D noise_tex : repeat_enable, filter_nearest;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.001, 0.3) = 0.04;
uniform float dissolve_pixel_resolution : hint_range(8.0, 128.0) = 64.0;

// === Color Override ===
uniform float white_mix : hint_range(0.0, 1.0) = 0.0;
uniform float black_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sprite_modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// === Fade-In ===
// Multipliziert ALPHA - fuer Crossfade beim Spawn.
// 0.0 = komplett unsichtbar, 1.0 = voll sichtbar.
uniform float fade_in : hint_range(0.0, 1.0) = 1.0;

// === Edge Glow ===
uniform vec4 edge_color : source_color = vec4(0.7, 0.2, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.12;

// === Wind ===
uniform vec2 wind_dir = vec2(1.0, -0.35);
uniform float wind_skew : hint_range(0.0, 1.0) = 0.0;

// === Z-Bias (zusaetzliche Sicherheit) ===
uniform float z_bias : hint_range(0.0, 0.05) = 0.01;


void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);

	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.z += z_bias;
	POSITION = PROJECTION_MATRIX * view_pos;
}


void fragment() {
	vec2 uv = UV;
	uv += wind_dir * wind_skew * (1.0 - UV.y) * 0.06;

	float col_u = uv.x;
	if (flip_h) col_u = 1.0 - col_u;
	int fx = frame % hframes;
	int fy = frame / hframes;
	vec2 atlas_uv = vec2(
		(float(fx) + col_u) / float(hframes),
		(float(fy) + uv.y) / float(vframes)
	);

	vec4 src = texture(albedo_tex, atlas_uv);
	src.rgb *= sprite_modulate.rgb;
	if (src.a < 0.01) discard;

	vec2 quant_uv = floor(uv * dissolve_pixel_resolution) / dissolve_pixel_resolution;
	float n = texture(noise_tex, quant_uv).r;
	if (n < dissolve) discard;

	vec3 col = mix(src.rgb, vec3(1.0), white_mix);
	col = mix(col, vec3(0.0), black_mix);

	float edge = smoothstep(dissolve, dissolve + edge_width, n);
	float dissolve_active = step(0.01, dissolve);
	vec3 glow = edge_color.rgb * (1.0 - edge) * emission_strength * dissolve_active;

	float a = src.a * (1.0 - smoothstep(0.85, 1.0, dissolve));
	a *= fade_in;  // Crossfade-Multiplikation

	ALBEDO = col + glow;
	ALPHA = a;
}
