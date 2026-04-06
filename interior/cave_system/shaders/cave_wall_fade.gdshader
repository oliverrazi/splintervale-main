// Cave Wall Fade Shader — Renders the visible edges of cave walls,
// transitioning from textured rock into the black void.
//
// This shader is applied to meshes that form the cave boundary.
// From top-down, these are the "cliffs" or "edges" the player sees
// looking down into the darkness or at the walls.
//
// Features:
//   • Texture-to-black gradient (smooth fade into void)
//   • Pixel art rock texture support
//   • Height-based shading (top = lighter, bottom = darker)
//   • Subtle color variation for organic look
//   • Vertex color support for manual fade control
//
// Mesh setup:
//   Create wall meshes that border the walkable floor.
//   Paint vertex color RED channel as fade gradient (1 = visible, 0 = fades to black).
//   OR rely on UV.y for automatic top-to-bottom darkening.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, unshaded;

// ── Textures ─────────────────────────────────────────────────────────────────

group_uniforms wall_textures;
uniform sampler2D texture_wall : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_detail : source_color, filter_nearest, repeat_enable;
uniform sampler2D texture_moss : source_color, filter_nearest, repeat_enable;

group_uniforms appearance;
uniform vec3 wall_tint : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 void_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float uv_scale : hint_range(0.1, 20.0) = 4.0;
uniform float detail_scale : hint_range(0.1, 20.0) = 6.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.25;
uniform float moss_scale : hint_range(0.1, 20.0) = 3.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.2;
uniform vec3 moss_tint : source_color = vec3(0.15, 0.22, 0.12);

group_uniforms fade;
uniform float fade_start : hint_range(0.0, 1.0) = 0.3;
uniform float fade_end : hint_range(0.0, 1.0) = 0.9;
uniform bool use_vertex_color_fade = true;
uniform float height_darkening : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 2.0) = 0.5;

group_uniforms variation;
uniform float color_variation : hint_range(0.0, 0.15) = 0.04;

// ── Utility ──────────────────────────────────────────────────────────────────

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Fragment ─────────────────────────────────────────────────────────────────

void fragment() {
	vec2 base_uv = UV * uv_scale;
	vec2 det_uv = UV * detail_scale;

	// ── Base Wall Texture ──
	vec3 wall = texture(texture_wall, base_uv).rgb;

	// ── Detail overlay ──
	vec3 detail = texture(texture_detail, det_uv).rgb;
	wall = mix(wall, wall * detail * 2.0, detail_strength);

	// ── Moss patches ──
	float moss_mask = texture(texture_moss, UV * moss_scale).r;
	moss_mask = smoothstep(0.5, 0.8, moss_mask) * moss_amount;
	wall = mix(wall, wall * moss_tint * 2.0, moss_mask);

	// ── Color variation ──
	float var_noise = value_noise(UV * 3.0);
	wall += vec3(var_noise - 0.5) * color_variation;

	// ── Apply tint ──
	wall *= wall_tint * brightness;

	// ── Fade to void ──
	float fade_factor;
	if (use_vertex_color_fade) {
		// Use vertex color red channel as visibility (1 = visible, 0 = void)
		fade_factor = COLOR.r;
	} else {
		// Use UV.y: top of wall (0) = visible, bottom (1) = fades to black
		fade_factor = 1.0 - UV.y;
	}

	// Smooth fade curve
	float fade = smoothstep(fade_end, fade_start, 1.0 - fade_factor);

	// ── Height-based darkening (simulate depth) ──
	float height_shade = mix(1.0 - height_darkening, 1.0, fade_factor);
	wall *= height_shade;

	// ── Final blend to void ──
	vec3 final_color = mix(void_color, wall, fade);

	ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
}
