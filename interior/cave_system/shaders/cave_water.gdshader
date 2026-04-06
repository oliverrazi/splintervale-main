// Cave Water Shader — Animated streams, puddles, and underground rivers.
//
// Features:
//   • Dual-layer animated UV scrolling for convincing flow
//   • Depth-based color gradient (shallow → deep)
//   • Caustic pattern overlay (animated light refractions)
//   • Edge foam / shore detection via alpha gradient
//   • Subtle surface distortion
//   • Pixel-art-friendly with filter_nearest
//
// Usage:
//   Apply to a Plane MeshInstance3D positioned at the water surface level.
//   The plane should be slightly below the cave floor level.
//   Use vertex color alpha for shore masks (0 = shore/edge, 1 = deep center).

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// ── Textures ─────────────────────────────────────────────────────────────────

group_uniforms water_textures;
uniform sampler2D texture_water : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_caustics : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_foam : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_flow_noise : hint_default_white, filter_nearest, repeat_enable;

group_uniforms water_colors;
uniform vec3 color_shallow : source_color = vec3(0.12, 0.18, 0.25);
uniform vec3 color_deep : source_color = vec3(0.03, 0.06, 0.10);
uniform vec3 color_foam : source_color = vec3(0.35, 0.38, 0.42);
uniform vec3 color_caustic : source_color = vec3(0.25, 0.35, 0.45);

group_uniforms flow;
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.3;
uniform float flow_speed_secondary : hint_range(0.0, 2.0) = 0.15;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.02;

group_uniforms appearance;
uniform float uv_scale : hint_range(0.1, 20.0) = 4.0;
uniform float caustic_scale : hint_range(0.1, 20.0) = 6.0;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.4;
uniform float foam_width : hint_range(0.0, 0.5) = 0.15;
uniform float foam_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
uniform float roughness : hint_range(0.0, 1.0) = 0.15;
uniform float specular : hint_range(0.0, 1.0) = 0.6;
uniform float depth_factor : hint_range(0.0, 1.0) = 0.5;

// ── Utility ──────────────────────────────────────────────────────────────────

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// ── Vertex ───────────────────────────────────────────────────────────────────

void vertex() {
	// Subtle vertex animation — gentle surface ripple
	float wave = sin(VERTEX.x * 3.0 + TIME * 1.5) * cos(VERTEX.z * 2.5 + TIME * 1.2);
	VERTEX.y += wave * 0.008;
}

// ── Fragment ─────────────────────────────────────────────────────────────────

void fragment() {
	vec2 base_uv = UV * uv_scale;
	float time = TIME;

	// ── Flow Animation (dual layer for natural look) ──
	vec2 flow_dir = normalize(flow_direction);
	vec2 flow_offset_1 = flow_dir * time * flow_speed;
	vec2 flow_offset_2 = flow_dir * time * flow_speed_secondary + vec2(0.37, 0.71);

	// Surface distortion from noise
	float noise_val = texture(texture_flow_noise, base_uv * 0.5 + flow_offset_2 * 0.3).r;
	vec2 distortion = vec2(noise_val - 0.5) * distortion_strength;

	// ── Water Texture (two layers blended) ──
	vec3 water_1 = texture(texture_water, base_uv + flow_offset_1 + distortion).rgb;
	vec3 water_2 = texture(texture_water, base_uv * 0.8 + flow_offset_2 - distortion).rgb;
	vec3 water_combined = mix(water_1, water_2, 0.5);

	// ── Depth Gradient ──
	// Vertex color alpha: 0 = shore/shallow, 1 = deep center
	float depth = COLOR.a * depth_factor;
	vec3 water_color = mix(color_shallow, color_deep, depth);
	water_color *= water_combined;

	// ── Caustics ──
	vec2 caustic_uv = UV * caustic_scale;
	vec2 caustic_offset = vec2(time * caustic_speed * 0.7, time * caustic_speed * 0.3);
	float caustic_1 = texture(texture_caustics, caustic_uv + caustic_offset).r;
	float caustic_2 = texture(texture_caustics, caustic_uv * 1.3 - caustic_offset * 0.6 + vec2(0.5)).r;
	// Intersection creates interesting patterns
	float caustic = min(caustic_1, caustic_2);
	caustic = smoothstep(0.3, 0.7, caustic) * caustic_intensity;
	water_color += color_caustic * caustic * (1.0 - depth * 0.5);

	// ── Shore Foam ──
	float shore_dist = COLOR.a; // 0 at edges
	float foam_mask = 1.0 - smoothstep(0.0, foam_width, shore_dist);
	// Animated foam line
	float foam_noise = texture(texture_foam, base_uv * 2.0 + flow_offset_1 * 0.5).r;
	float foam = foam_mask * step(0.4, foam_noise) * foam_intensity;
	water_color = mix(water_color, color_foam, foam);

	// ── Final Opacity ──
	// Fade at edges for soft shore transition
	float edge_alpha = smoothstep(0.0, 0.05, shore_dist);
	float final_alpha = opacity * edge_alpha;

	// ── Output ──
	ALBEDO = water_color;
	ALPHA = final_alpha;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.05;
	// Subtle emission for a magical cave-water feel
	EMISSION = water_color * caustic * 0.15;
}
