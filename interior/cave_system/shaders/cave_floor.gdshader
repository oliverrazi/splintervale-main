// Cave Floor Shader — Professional stone/rock floor for 2.5D top-down caves.
//
// Features:
//   • Base texture with detail overlay for tiling breakup
//   • Wetness zones (paint via vertex color or uniform)
//   • Edge darkening / ambient occlusion simulation
//   • Subtle color variation to prevent visible tiling
//   • Specular highlights on wet areas
//   • Optional crack / crevice overlay
//
// Textures you need to prepare:
//   texture_albedo     — Main stone texture (pixel art, tiling)
//   texture_detail     — Detail / variation overlay (subtle noise, cracks)
//   texture_normal     — Normal map for the stone (optional but recommended)
//   texture_wetness    — Wetness mask (white = wet, black = dry). Can be a painted mask.
//   texture_ao         — Ambient occlusion / edge darkening mask (bake or paint)

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Textures ─────────────────────────────────────────────────────────────────

group_uniforms base_textures;
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_detail : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_normal : hint_roughness_normal, filter_nearest, repeat_enable;
uniform sampler2D texture_ao : hint_default_white, filter_nearest, repeat_enable;

group_uniforms wetness;
uniform sampler2D texture_wetness : hint_default_black, filter_nearest, repeat_enable;
uniform float wetness_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wet_tint : source_color = vec3(0.03, 0.04, 0.06);
uniform float wet_darkening : hint_range(0.0, 0.5) = 0.3;
uniform float wet_specular : hint_range(0.0, 1.0) = 0.7;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.2;

group_uniforms appearance;
uniform vec3 base_tint : source_color = vec3(1.0);
uniform float uv_scale : hint_range(0.1, 20.0) = 4.0;
uniform float detail_uv_scale : hint_range(0.1, 20.0) = 8.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;

group_uniforms variation;
uniform float color_variation : hint_range(0.0, 0.2) = 0.05;
uniform float variation_scale : hint_range(0.1, 10.0) = 2.0;

group_uniforms edge_darkening;
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.6;
// Edge darkening is driven by vertex color alpha or AO texture.
// Paint vertex color alpha = 0 at cave edges, 1 in center.

// ── Utility Functions ────────────────────────────────────────────────────────

// Simple hash for pseudo-random variation
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise for smooth color variation
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Fragment Shader ──────────────────────────────────────────────────────────

void fragment() {
	vec2 base_uv = UV * uv_scale;
	vec2 detail_uv = UV * detail_uv_scale;

	// ── Base Albedo ──
	vec3 albedo = texture(texture_albedo, base_uv).rgb;

	// ── Detail Overlay (breaks up tiling) ──
	vec3 detail = texture(texture_detail, detail_uv).rgb;
	albedo = mix(albedo, albedo * detail * 2.0, detail_strength);

	// ── Color Variation (prevents visible tiling) ──
	float variation = value_noise(UV * variation_scale);
	vec3 var_offset = vec3(variation - 0.5) * color_variation * 2.0;
	albedo += var_offset;

	// ── Apply Base Tint ──
	albedo *= base_tint;

	// ── Ambient Occlusion / Edge Darkening ──
	float ao = texture(texture_ao, UV).r; // UV (not tiled) for AO mask
	float edge = COLOR.a; // Vertex color alpha for edge proximity (1=center, 0=edge)
	float combined_ao = mix(1.0, ao, ao_strength) * mix(1.0 - edge_darkness, 1.0, edge);
	albedo *= combined_ao;

	// ── Wetness ──
	float wet_mask = texture(texture_wetness, UV).r * wetness_strength;
	// Darken wet areas
	albedo = mix(albedo, albedo * (1.0 - wet_darkening) + wet_tint, wet_mask);

	// ── Normal Map ──
	vec3 normal_sample = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP = normal_sample;
	NORMAL_MAP_DEPTH = normal_strength;

	// ── Material Properties ──
	float roughness = mix(base_roughness, wet_roughness, wet_mask);
	float specular = mix(0.2, wet_specular, wet_mask);

	// ── Output ──
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	SPECULAR = specular;
	AO = combined_ao;
	AO_LIGHT_AFFECT = 0.6;
}
