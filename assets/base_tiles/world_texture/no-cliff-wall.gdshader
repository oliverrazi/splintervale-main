shader_type spatial;

// ============================================================
// Cliff-Shader (World-Space Triplanar) — Godot 4.5 — v6
//
// Fels:  Triplanar in Weltkoordinaten
// Gras:  Quelle 1: Hoehenbasierter Saum ab Modul-Oberkante
//        Quelle 2: VERTEX-COLOR-MASKE — in Blender ROT (1,0,0)
//                  malen, wo Gras sein soll (Rampen-Oberseiten,
//                  Ueberhaenge, Moosflaechen ...).
//                  Unbemalte Meshes (= weiss) sind unveraendert.
//        Wirksam ist das Maximum beider Quellen.
// v5:    Detiling (rotierte Zweit-Samples in Noise-Flecken)
//
// Texturformat wie Terrain3D:
//   Albedo: RGB = Albedo, A = Height
//   Normal: RGB = Normal (OpenGL/Y+), A = Roughness
//   Import der Normal-Textur: "Normal Map: Disabled"!
// ============================================================

// --- Fels ---
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_uv_scale : hint_range(0.05, 20.0) = 2.0; // Kacheln pro Meter
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float rock_normal_strength : hint_range(0.0, 2.0) = 1.0;

// --- Gras ---
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_uv_scale : hint_range(0.05, 20.0) = 2.0;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform float grass_normal_strength : hint_range(0.0, 2.0) = 1.0;

// Quelle 1: Hoehen-Saum
uniform float grass_top_level = 1.0;
uniform float grass_band_depth : hint_range(0.0, 1.0) = 0.08;
uniform float grass_band_softness : hint_range(0.001, 0.3) = 0.03;
uniform float grass_band_noise : hint_range(0.0, 0.5) = 0.06;
uniform float grass_noise_scale : hint_range(0.1, 30.0) = 8.0;

// Quelle 2: Vertex-Color-Maske
// Wie stark Noise die gemalte Grenze ausfranst
uniform float vcol_edge_noise : hint_range(0.0, 0.5) = 0.25;

// --- Detiling ---
uniform float detile_amount : hint_range(0.0, 1.0) = 0.8;
uniform float detile_scale : hint_range(0.05, 5.0) = 0.35;
uniform float detile_angle : hint_range(0.0, 6.283) = 2.4;

// --- Reflexion ---
uniform float specular_amount : hint_range(0.0, 1.0) = 0.1;

// --- AO (Approximation aus Height-Kanal) ---
uniform float ao_strength : hint_range(0.0, 1.0) = 0.5;
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.5;

// --- Makro-Variation ---
uniform float macro_scale : hint_range(0.01, 2.0) = 0.15;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.12;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_dist_top;
varying float v_grass_paint; // 1 = rot gemalt (Gras), 0 = unbemalt

const vec2 DETILE_OFFSET = vec2(4.37, 7.71);


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	v_dist_top = (grass_top_level - VERTEX.y) * scale_y;
	// Rot gemalt (1,0,0): Blau- und Gruenkanal fallen auf 0.
	// Unbemalt liest sich als Weiss (1,1,1) -> paint = 0.
	v_grass_paint = clamp(COLOR.r - max(COLOR.g, COLOR.b), 0.0, 1.0);
}


float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 rot2(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float detile_mask(vec2 uv) {
	return detile_amount * smoothstep(0.35, 0.65, value_noise(uv * detile_scale));
}

vec4 sample_color_detiled(sampler2D tex, vec2 uv, float uv_scale) {
	float m = detile_mask(uv);
	vec4 s0 = texture(tex, uv * uv_scale);
	vec4 s1 = texture(tex, rot2(uv, detile_angle) * uv_scale + DETILE_OFFSET);
	return mix(s0, s1, m);
}

vec4 sample_nr_detiled(sampler2D tex, vec2 uv, float uv_scale) {
	float m = detile_mask(uv);
	vec4 s0 = texture(tex, uv * uv_scale);
	vec4 s1 = texture(tex, rot2(uv, detile_angle) * uv_scale + DETILE_OFFSET);
	vec3 n1 = s1.rgb * 2.0 - 1.0;
	n1.xy = rot2(n1.xy, -detile_angle);
	s1.rgb = n1 * 0.5 + 0.5;
	return mix(s0, s1, m);
}

vec3 triplanar_normal(vec3 tnx, vec3 tny, vec3 tnz, vec3 wn, vec3 w) {
	tnx = vec3(tnx.xy + wn.zy, abs(tnx.z) * wn.x);
	tny = vec3(tny.xy + wn.xz, abs(tny.z) * wn.y);
	tnz = vec3(tnz.xy + wn.xy, abs(tnz.z) * wn.z);
	return normalize(tnx.zyx * w.x + tny.xzy * w.y + tnz.xyz * w.z);
}


void fragment() {
	vec3 wn = normalize(v_world_normal);
	vec3 wp = v_world_pos;

	// --- Triplanar-Gewichte ---
	vec3 w = pow(abs(wn), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);

	vec2 uv_x = wp.zy;
	vec2 uv_y = wp.xz;
	vec2 uv_z = wp.xy;

	// --- Fels: Albedo + Height ---
	vec4 rax = sample_color_detiled(rock_albedo, uv_x, rock_uv_scale);
	vec4 ray = sample_color_detiled(rock_albedo, uv_y, rock_uv_scale);
	vec4 raz = sample_color_detiled(rock_albedo, uv_z, rock_uv_scale);
	vec3 rock_col = rax.rgb * w.x + ray.rgb * w.y + raz.rgb * w.z;
	float rock_height = rax.a * w.x + ray.a * w.y + raz.a * w.z;

	// --- Fels: Normal + Roughness ---
	vec4 rsx = sample_nr_detiled(rock_normal_rough, uv_x, rock_uv_scale);
	vec4 rsy = sample_nr_detiled(rock_normal_rough, uv_y, rock_uv_scale);
	vec4 rsz = sample_nr_detiled(rock_normal_rough, uv_z, rock_uv_scale);
	float rock_rough = rsx.a * w.x + rsy.a * w.y + rsz.a * w.z;
	vec3 rock_wn = triplanar_normal(
		rsx.rgb * 2.0 - 1.0, rsy.rgb * 2.0 - 1.0, rsz.rgb * 2.0 - 1.0, wn, w);
	rock_wn = normalize(mix(wn, rock_wn, rock_normal_strength));

	// --- Gras: Albedo + Height ---
	vec4 gax = sample_color_detiled(grass_albedo, uv_x, grass_uv_scale);
	vec4 gay = sample_color_detiled(grass_albedo, uv_y, grass_uv_scale);
	vec4 gaz = sample_color_detiled(grass_albedo, uv_z, grass_uv_scale);
	vec3 grass_col = (gax.rgb * w.x + gay.rgb * w.y + gaz.rgb * w.z) * grass_tint.rgb;
	float grass_height = gax.a * w.x + gay.a * w.y + gaz.a * w.z;

	// --- Gras: Normal + Roughness ---
	vec4 gsx = sample_nr_detiled(grass_normal_rough, uv_x, grass_uv_scale);
	vec4 gsy = sample_nr_detiled(grass_normal_rough, uv_y, grass_uv_scale);
	vec4 gsz = sample_nr_detiled(grass_normal_rough, uv_z, grass_uv_scale);
	float grass_rough = gsx.a * w.x + gsy.a * w.y + gsz.a * w.z;
	vec3 grass_wn = triplanar_normal(
		gsx.rgb * 2.0 - 1.0, gsy.rgb * 2.0 - 1.0, gsz.rgb * 2.0 - 1.0, wn, w);
	grass_wn = normalize(mix(wn, grass_wn, grass_normal_strength));

	// --- Gras-Maske ---
	float n01 = value_noise(wp.xz * grass_noise_scale);

	// Quelle 1: Hoehen-Saum ab Oberkante
	float band = grass_band_depth + n01 * grass_band_noise;
	float band_mask = 1.0 - smoothstep(
		band - grass_band_softness,
		band + grass_band_softness,
		v_dist_top);

	// Quelle 2: Vertex-Paint. Noise verschiebt die Schwelle innerhalb
	// des gemalten Farbverlaufs -> ausgefranste, organische Grenze.
	float th = 0.5 + (n01 - 0.5) * 2.0 * vcol_edge_noise;
	float paint_mask = smoothstep(th - 0.15, th + 0.15, v_grass_paint);

	float grass_mask = max(band_mask, paint_mask);

	// --- Makro-Variation ---
	float mv = value_noise(wp.xz * macro_scale);
	float macro_mul = mix(1.0 - macro_strength, 1.0 + macro_strength, mv);

	// --- Kombinieren ---
	float height = mix(rock_height, grass_height, grass_mask);
	vec3 final_wn = normalize(mix(rock_wn, grass_wn, grass_mask));

	ALBEDO = mix(rock_col, grass_col, grass_mask) * macro_mul;
	ROUGHNESS = mix(rock_rough, grass_rough, grass_mask);
	SPECULAR = specular_amount;
	NORMAL = normalize((VIEW_MATRIX * vec4(final_wn, 0.0)).xyz);

	AO = mix(1.0, height, ao_strength);
	AO_LIGHT_AFFECT = ao_light_affect;
}
