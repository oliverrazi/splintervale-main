// Cave Caustics Shader — Projects animated water light refraction patterns
// onto nearby cave floor and walls.
//
// Usage:
//   Apply to a large, flat QuadMesh positioned just above the floor near water.
//   Set the mesh to be slightly transparent and additive-blended.
//   This creates the effect of light bouncing off water onto stone surfaces.
//
// The caustic pattern is generated procedurally — no texture needed,
// but you can supply one for a more controlled pixel-art look.

shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

group_uniforms caustics;
uniform sampler2D texture_caustics : hint_default_white, filter_nearest, repeat_enable;
uniform bool use_procedural = true;
uniform vec3 caustic_color : source_color = vec3(0.15, 0.2, 0.3);
uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform float speed : hint_range(0.0, 2.0) = 0.3;
uniform float scale : hint_range(0.1, 20.0) = 5.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.4;

group_uniforms shape;
uniform float falloff_radius : hint_range(0.1, 20.0) = 3.0;
uniform float falloff_softness : hint_range(0.0, 5.0) = 1.5;
uniform vec2 center_offset = vec2(0.0, 0.0);

// ── Procedural Caustics ──────────────────────────────────────────────────────

// Voronoi-based caustic pattern
vec2 random2(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453);
}

float voronoi(vec2 uv, float t) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);

	float min_dist = 1.0;
	float second_dist = 1.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = random2(i + neighbor);
			point = 0.5 + 0.5 * sin(t * 0.8 + 6.2831 * point);
			vec2 diff = neighbor + point - f;
			float dist = length(diff);

			if (dist < min_dist) {
				second_dist = min_dist;
				min_dist = dist;
			} else if (dist < second_dist) {
				second_dist = dist;
			}
		}
	}

	// Edge detection between voronoi cells = caustic lines
	return second_dist - min_dist;
}

float caustic_pattern(vec2 uv, float t) {
	// Two layers at different scales for complexity
	float c1 = voronoi(uv * scale, t * speed);
	float c2 = voronoi(uv * scale * 1.4 + vec2(3.7, 1.2), t * speed * 0.7 + 2.0);

	// Combine — intersection of two patterns
	float caustic = min(c1, c2);

	// Sharpen for a more defined look
	caustic = smoothstep(0.0, 0.15, caustic);
	caustic = 1.0 - caustic;
	caustic = pow(caustic, 2.0);

	return caustic;
}

// ── Fragment ─────────────────────────────────────────────────────────────────

void fragment() {
	float caustic;

	if (use_procedural) {
		caustic = caustic_pattern(UV, TIME);
	} else {
		// Texture-based with animation
		vec2 uv1 = UV * scale + vec2(TIME * speed * 0.3, TIME * speed * 0.1);
		vec2 uv2 = UV * scale * 1.3 - vec2(TIME * speed * 0.2, TIME * speed * 0.25) + vec2(0.5);
		float c1 = texture(texture_caustics, uv1).r;
		float c2 = texture(texture_caustics, uv2).r;
		caustic = min(c1, c2);
		caustic = smoothstep(0.3, 0.7, caustic);
	}

	// Distance-based falloff from the water source center
	vec2 center = vec2(0.5) + center_offset;
	float dist = length(UV - center) * 2.0; // Normalize to 0-1 range roughly
	float falloff = 1.0 - smoothstep(falloff_radius * 0.1, (falloff_radius + falloff_softness) * 0.1, dist);

	// Final
	float final_intensity = caustic * intensity * falloff;
	vec3 color = caustic_color * final_intensity;

	ALBEDO = color;
	ALPHA = final_intensity * opacity;
}
