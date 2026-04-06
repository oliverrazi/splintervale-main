// God Ray Shader — apply to a QuadMesh or PlaneMesh
// Creates a soft, animated light beam effect
// Use with MeshInstance3D, billboard disabled, transparency enabled

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 ray_color : source_color = vec4(1.0, 0.95, 0.8, 0.3);
uniform float intensity : hint_range(0.0, 2.0) = 0.5;

// Shape
uniform float fade_top : hint_range(0.0, 1.0) = 0.1;    // Fade at top of beam
uniform float fade_bottom : hint_range(0.0, 1.0) = 0.4;  // Fade at bottom (wider = softer ground contact)
uniform float fade_edges : hint_range(0.0, 1.0) = 0.3;   // Horizontal edge softness

// Animation
uniform float sway_speed : hint_range(0.0, 2.0) = 0.3;
uniform float sway_amount : hint_range(0.0, 0.2) = 0.05;
uniform float flicker_speed : hint_range(0.0, 5.0) = 1.5;
uniform float flicker_amount : hint_range(0.0, 0.5) = 0.15;

// Dust particles
uniform bool dust_enabled = true;
uniform float dust_density : hint_range(0.0, 100.0) = 40.0;
uniform float dust_brightness : hint_range(0.0, 2.0) = 0.6;
uniform float dust_speed : hint_range(0.0, 2.0) = 0.5;
uniform float dust_size : hint_range(0.001, 0.02) = 0.006;


// Simple hash for dust particles
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float dust_pattern(vec2 uv, float time_val) {
	float dust = 0.0;
	for (float i = 0.0; i < 3.0; i += 1.0) {
		vec2 offset = vec2(
			sin(time_val * dust_speed * (0.5 + i * 0.3) + i * 1.7) * 0.1,
			-time_val * dust_speed * (0.3 + i * 0.2)
		);
		vec2 grid_uv = (uv + offset) * dust_density * (1.0 + i * 0.5);
		vec2 cell = floor(grid_uv);
		vec2 local = fract(grid_uv) - 0.5;

		float h = hash(cell + i * 100.0);
		vec2 particle_pos = vec2(h, fract(h * 37.0)) - 0.5;
		float d = length(local - particle_pos * 0.4);

		float particle = smoothstep(dust_size, 0.0, d) * h;
		dust += particle;
	}
	return dust;
}

void fragment() {
	vec2 uv = UV;

	// Soft beam shape
	float vertical = 1.0;
	vertical *= smoothstep(0.0, fade_top, uv.y);          // Fade in from top
	vertical *= smoothstep(1.0, 1.0 - fade_bottom, uv.y); // Fade out at bottom

	float horizontal = 1.0;
	// Beam widens toward bottom
	float beam_width = mix(0.3, 0.5, uv.y);
	float dist_from_center = abs(uv.x - 0.5);
	horizontal = smoothstep(beam_width, beam_width - fade_edges, dist_from_center);

	float beam = vertical * horizontal;

	// Sway animation
	float sway = sin(TIME * sway_speed + uv.y * 2.0) * sway_amount;
	beam *= smoothstep(beam_width + sway, beam_width - fade_edges + sway, dist_from_center);

	// Flicker
	float flicker = 1.0 - flicker_amount * (sin(TIME * flicker_speed) * 0.5 + 0.5)
					* (sin(TIME * flicker_speed * 1.7 + 1.0) * 0.5 + 0.5);

	// Dust particles
	float dust = 0.0;
	if (dust_enabled) {
		dust = dust_pattern(uv, TIME) * dust_brightness * beam;
	}

	float final_alpha = (beam * intensity * flicker) + dust;
	ALBEDO = ray_color.rgb;
	ALPHA = final_alpha * ray_color.a;
}
