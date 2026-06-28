shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// === Wall Fade ===
uniform float wall_fade_start : hint_range(0.0, 0.3, 0.01) = 0.05;
uniform float wall_fade_range : hint_range(0.05, 1.5, 0.01) = 0.4;

uniform sampler2D noise_tex    : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_pattern : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float flow_speed   : hint_range(0.0, 4.0, 0.05) = 0.8;
uniform float inner_solid  : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float outer_radius : hint_range(0.0, 0.5, 0.01) = 0.45;
uniform float density      : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float opacity      : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float emission     : hint_range(0.0, 2.0, 0.05) = 0.25;

uniform float ring_count     : hint_range(2.0, 20.0, 0.5) = 8.0;
uniform float ring_speed     : hint_range(0.0, 4.0, 0.05) = 1.5;
uniform float ring_strength  : hint_range(0.0, 2.0, 0.01) = 0.8;
uniform float ring_sharpness : hint_range(1.0, 8.0, 0.1) = 2.5;
uniform float angular_chaos  : hint_range(0.0, 1.0, 0.01) = 0.15;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	// Konzentrische Wellen
	float ring_phase = dist * ring_count - TIME * ring_speed;
	float ring_wave = sin(ring_phase * 6.2831) * 0.5 + 0.5;
	ring_wave = pow(ring_wave, ring_sharpness);
	
	float angular_noise = texture(noise_tex, vec2(angle / 6.2831, dist) * vec2(3.0, 4.0) + vec2(0.0, -TIME * 0.5)).r;
	angular_noise = mix(1.0, angular_noise, angular_chaos);

	vec2 polar_uv = vec2(angle / 6.2831 + TIME * 0.02, dist);
	vec2 scroll_uv = polar_uv * vec2(3.0, 4.0) + vec2(0.0, -TIME * flow_speed);
	float pattern = texture(foam_pattern, scroll_uv).r;
	float noise = texture(noise_tex, polar_uv * vec2(5.0, 7.0) + vec2(TIME * 0.1, 0.0)).r;

	float foam_detail = smoothstep(1.0 - density, 1.0, pattern * noise);
	float foam_rings = ring_wave * ring_strength * angular_noise;
	float foam = clamp(foam_detail + foam_rings, 0.0, 1.0);

	float edge_noise = texture(noise_tex, vec2(angle / 6.2831 * 4.0, TIME * 0.1)).r;
	float perturbed_dist = dist + (edge_noise - 0.5) * 0.05;

	float center_solid = 1.0 - smoothstep(0.0, inner_solid, dist);
	float outer_fade = 1.0 - smoothstep(outer_radius * 0.25, outer_radius, perturbed_dist);
	float radial_mask  = smoothstep(inner_solid, inner_solid + 0.05, dist) * outer_fade;

	float final_foam = clamp(foam * radial_mask + center_solid, 0.0, 1.0);

	// === NEU: Y-Aware Wall Fade in Weltkoordinaten ===
	float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 scene_ndc  = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 scene_view = INV_PROJECTION_MATRIX * scene_ndc;
	scene_view /= scene_view.w;
	
	vec3 scene_world = (INV_VIEW_MATRIX * scene_view).xyz;
	vec3 disc_world  = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Wenn Szenen-Y deutlich über Disc-Y liegt → da ragt was hoch (Felswand) → ausblenden
	float y_above = max(scene_world.y - disc_world.y, 0.0);
	float wall_fade = 1.0 - smoothstep(wall_fade_start, wall_fade_start + wall_fade_range, y_above);

	ALBEDO   = foam_color.rgb;
	EMISSION = foam_color.rgb * emission;
	ALPHA    = final_foam * opacity * wall_fade;
}