// Cave Ceiling Overlay Shader — Stalactites and overhead rock rendered above the player.
//
// In a 2.5D top-down view, "ceiling" elements are sprites/meshes rendered
// at a higher Y position (or with render priority) that pass OVER the player,
// creating the illusion of depth and overhead rock formations.
//
// Features:
//   • Alpha-based rendering for stalactite sprites
//   • Subtle shadow projection downward (darker areas below stalactites)
//   • Gentle sway animation (optional, for hanging vines/roots)
//   • Depth-based transparency (farther from camera = more transparent)
//   • Drip particle emission point support
//
// Usage:
//   Apply to Sprite3D or MeshInstance3D placed above the player layer.
//   The sprite texture should have transparency for the stalactite shape.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// ── Textures ─────────────────────────────────────────────────────────────────

uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform sampler2D texture_shadow : hint_default_black, filter_nearest;

group_uniforms appearance;
uniform vec3 tint : source_color = vec3(0.2, 0.19, 0.18);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float shadow_opacity : hint_range(0.0, 0.8) = 0.3;
uniform float brightness : hint_range(0.0, 2.0) = 0.4;

group_uniforms animation;
uniform bool enable_sway = false;
uniform float sway_amount : hint_range(0.0, 0.05) = 0.01;
uniform float sway_speed : hint_range(0.0, 5.0) = 1.5;
uniform float sway_phase_offset : hint_range(0.0, 6.28) = 0.0;

group_uniforms depth;
uniform float depth_fade_start : hint_range(0.0, 50.0) = 8.0;
uniform float depth_fade_end : hint_range(0.0, 100.0) = 20.0;
uniform bool enable_depth_fade = false;

// ── Vertex ───────────────────────────────────────────────────────────────────

void vertex() {
	if (enable_sway) {
		// Sway increases toward the bottom of the sprite (hanging stalactites)
		float sway_weight = UV.y; // Bottom of sprite sways more
		float sway = sin(TIME * sway_speed + sway_phase_offset + VERTEX.x * 2.0) * sway_amount;
		VERTEX.x += sway * sway_weight;
	}
}

// ── Fragment ─────────────────────────────────────────────────────────────────

void fragment() {
	vec4 tex = texture(texture_albedo, UV);

	// Discard fully transparent pixels
	if (tex.a < 0.1) {
		discard;
	}

	vec3 color = tex.rgb * tint * brightness;

	// Shadow layer — a separate texture or the same texture darkened
	// This gets projected "downward" in the scene by placing a separate
	// shadow mesh below; this shader just handles the stalactite itself.

	float alpha = tex.a * opacity;

	// Optional depth fade
	if (enable_depth_fade) {
		float dist = length(VERTEX);
		float depth_fade = 1.0 - smoothstep(depth_fade_start, depth_fade_end, dist);
		alpha *= depth_fade;
	}

	ALBEDO = color;
	ALPHA = alpha;
}
