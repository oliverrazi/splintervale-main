// Cave Rock Shader — For 3D rock geometry (walls, overhangs, stalactites).
//
// Unlike cave_wall_fade (which fades flat surfaces to void), this shader
// is designed for actual 3D rock meshes with real geometry and depth.
//
// Features:
//   • Height-based darkening (lower parts darker = depth illusion)
//   • World-space triplanar texturing (no UV seams on irregular rocks)
//   • Moss/lichen on upward-facing surfaces
//   • Wetness on lower surfaces (drip zones)
//   • Per-face detail variation (breaks tiling across large surfaces)
//   • Rim lighting for edge definition against dark backgrounds
//   • Bottom-void fade (rock meshes fade to black at their base)
//
// Apply to: MeshInstance3D rock meshes (from Blender or procedural)

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Textures ─────────────────────────────────────────────────────────────────

group_uniforms rock_textures;
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_normal : hint_roughness_normal, filter_nearest, repeat_enable;
uniform sampler2D texture_detail : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_moss : source_color, filter_nearest, repeat_enable;

group_uniforms color;
uniform vec3 wall_tint : source_color = vec3(0.22, 0.20, 0.18);
uniform float brightness : hint_range(0.0, 2.0) = 0.45;
uniform float color_variation : hint_range(0.0, 0.2) = 0.06;

group_uniforms triplanar;
uniform float triplanar_scale : hint_range(0.1, 10.0) = 2.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float detail_scale : hint_range(0.1, 20.0) = 4.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;

group_uniforms height_shading;
uniform float height_darkening : hint_range(0.0, 1.0) = 0.6;
uniform float height_reference : hint_range(-5.0, 10.0) = 0.0;
uniform float height_range : hint_range(0.5, 10.0) = 3.0;
uniform float bottom_fade_start : hint_range(-5.0, 5.0) = 0.0;
uniform float bottom_fade_range : hint_range(0.1, 3.0) = 0.8;

group_uniforms moss;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.15;
uniform vec3 moss_tint : source_color = vec3(0.12, 0.18, 0.10);
uniform float moss_height_min : hint_range(-2.0, 5.0) = 0.5;
uniform float moss_normal_threshold : hint_range(0.0, 1.0) = 0.6;

group_uniforms wetness;
uniform float wetness : hint_range(0.0, 1.0) = 0.2;
uniform float wet_height_max : hint_range(-2.0, 5.0) = 0.8;
uniform vec3 wet_tint : source_color = vec3(0.05, 0.06, 0.08);
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.2;

group_uniforms rim_light;
uniform bool enable_rim = true;
uniform vec3 rim_color : source_color = vec3(0.15, 0.14, 0.13);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.25;

group_uniforms surface;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// ── Varying ──────────────────────────────────────────────────────────────────

varying vec3 world_pos;
varying vec3 world_normal;

// ── Vertex ───────────────────────────────────────────────────────────────────

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// ── Utility ──────────────────────────────────────────────────────────────────

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Triplanar mapping — samples texture from 3 axes and blends based on normal
vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal, float scale, float sharpness) {
	// Blend weights from world normal
	vec3 blend = pow(abs(normal), vec3(sharpness));
	blend /= (blend.x + blend.y + blend.z);

	// Sample from each axis
	vec3 x_sample = texture(tex, pos.yz * scale).rgb;
	vec3 y_sample = texture(tex, pos.xz * scale).rgb;
	vec3 z_sample = texture(tex, pos.xy * scale).rgb;

	return x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
}

// ── Fragment ─────────────────────────────────────────────────────────────────

void fragment() {
	vec3 wpos = world_pos;
	vec3 wnorm = normalize(world_normal);

	// ── Base Albedo (Triplanar) ──
	vec3 albedo = triplanar_sample(texture_albedo, wpos, wnorm, triplanar_scale, triplanar_sharpness);

	// ── Detail Overlay (breaks tiling) ──
	vec3 detail = triplanar_sample(texture_detail, wpos, wnorm, detail_scale, triplanar_sharpness);
	albedo = mix(albedo, albedo * detail * 2.0, detail_strength);

	// ── Per-rock color variation ──
	float var_hash = hash(floor(wpos * 0.5));
	albedo += vec3(var_hash - 0.5) * color_variation;

	// ── Apply base tint ──
	albedo *= wall_tint * brightness;

	// ── Height-based darkening ──
	float height_factor = clamp((wpos.y - height_reference) / height_range, 0.0, 1.0);
	float height_shade = mix(1.0 - height_darkening, 1.0, height_factor);
	albedo *= height_shade;

	// ── Bottom fade to void ──
	float bottom_fade = smoothstep(bottom_fade_start, bottom_fade_start + bottom_fade_range, wpos.y);
	albedo *= bottom_fade;

	// ── Moss on upward-facing surfaces ──
	float up_dot = dot(wnorm, vec3(0.0, 1.0, 0.0));
	float moss_mask = smoothstep(moss_normal_threshold - 0.1, moss_normal_threshold + 0.1, up_dot);
	float moss_height_mask = smoothstep(moss_height_min - 0.3, moss_height_min + 0.5, wpos.y);
	vec3 moss_color = triplanar_sample(texture_moss, wpos, wnorm, triplanar_scale * 1.5, triplanar_sharpness);
	float final_moss = moss_mask * moss_height_mask * moss_amount;
	albedo = mix(albedo, moss_color * moss_tint * 2.0, final_moss);

	// ── Wetness on lower surfaces ──
	float wet_mask = (1.0 - smoothstep(wet_height_max - 0.5, wet_height_max + 0.3, wpos.y)) * wetness;
	// Prefer downward or vertical surfaces for drip wetness
	float drip_factor = 1.0 - max(up_dot, 0.0);
	wet_mask *= (0.5 + drip_factor * 0.5);
	albedo = mix(albedo, albedo * 0.7 + wet_tint, wet_mask);

	// ── Normal Map (Triplanar) ──
	vec3 norm_sample = triplanar_sample(texture_normal, wpos, wnorm, triplanar_scale, triplanar_sharpness);
	NORMAL_MAP = norm_sample;
	NORMAL_MAP_DEPTH = normal_strength;

	// ── Roughness ──
	float roughness = mix(base_roughness, wet_roughness, wet_mask);
	roughness = mix(roughness, roughness * 1.1, final_moss); // Moss is slightly rougher

	// ── Rim Light ──
	if (enable_rim) {
		float rim = 1.0 - max(dot(wnorm, VIEW), 0.0);
		rim = pow(rim, rim_power) * rim_intensity;
		// Only apply rim light where the rock is visible (not in void fade)
		albedo += rim_color * rim * bottom_fade * height_shade;
	}

	// ── Output ──
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness, 0.0, 1.0);
	SPECULAR = mix(0.15, 0.5, wet_mask); // Wet rocks are more specular
	METALLIC = 0.0;
}
