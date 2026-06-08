shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D flow_noise_a   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_noise_b   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_pattern   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear, repeat_enable;

uniform vec4 color_top    : source_color = vec4(0.55, 0.82, 0.92, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.28, 0.62, 0.74, 1.0);
uniform vec4 foam_color   : source_color = vec4(0.92, 0.97, 1.0, 1.0);

uniform float flow_speed : hint_range(0.0, 6.0, 0.05) = 1.6;
uniform vec2  tiling_a   = vec2(1.0, 3.0);
uniform vec2  tiling_b   = vec2(2.3, 5.7);
uniform float distortion : hint_range(0.0, 0.2, 0.005) = 0.04;

// Foam (insgesamt etwas gedämpft für natürlicheren Look)
uniform float foam_density     : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float top_foam_band    : hint_range(0.0, 0.3, 0.01) = 0.06;
uniform float bottom_foam_band : hint_range(0.0, 0.4, 0.01) = 0.18;
uniform float foam_emission    : hint_range(0.0, 2.0, 0.05) = 0.4;

// === Natural Edges (neu) ===
uniform float edge_softness    : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float edge_noise_amp   : hint_range(0.0, 0.2, 0.005) = 0.06;
uniform float top_fade         : hint_range(0.0, 0.3, 0.01) = 0.05;
uniform float bottom_fade      : hint_range(0.0, 0.2, 0.01) = 0.03;

// === Transluzenz (neu/anders) ===
uniform float opacity_base     : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float opacity_foam     : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float backlight_strength : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float lip_curve_band  : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float lip_curve_depth : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float lip_curve_drop  : hint_range(0.0, 0.3, 0.01) = 0.04;

uniform float roughness        : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float metallic         : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float normal_strength  : hint_range(0.0, 2.0, 0.05) = 0.6;

void vertex() {
	// Im oberen Band sanft nach vorne wölben (über die Klippenkante fließen)
	float curve_t = smoothstep(lip_curve_band, 0.0, UV.y);
	// Smoothstep nochmal für S-Curve-Charakter (sanfter Übergang)
	curve_t = curve_t * curve_t * (3.0 - 2.0 * curve_t);
	
	VERTEX.z += curve_t * lip_curve_depth;  // nach vorne wölben
	VERTEX.y -= curve_t * lip_curve_drop;   // leicht absinken (Schwerkraft visualisiert)
}

void fragment() {
	vec2 uv = UV;

	vec2 uv_a = uv * tiling_a - vec2(0.0, TIME * flow_speed);
	vec2 uv_b = uv * tiling_b - vec2(0.0, TIME * flow_speed * 1.7);

	float n_a = texture(flow_noise_a, uv_a).r;
	float n_b = texture(flow_noise_b, uv_b).r;

	vec2 warped_uv = uv + vec2((n_b - 0.5) * distortion, 0.0);
	vec3 water = mix(color_top.rgb, color_bottom.rgb, warped_uv.y);

	// === Natürlicher Silhouettenrand ===
	// Distanz zum nächsten horizontalen Rand (0 außen, 0.5 in der Mitte)
	float dx = min(uv.x, 1.0 - uv.x);
	// Animiertes Noise um die Kante "auszufransen"
	float edge_n = texture(flow_noise_b, uv * vec2(3.0, 0.7) + vec2(0.0, TIME * 0.15)).r;
	float silhouette_dx = dx + (edge_n - 0.5) * edge_noise_amp;
	float edge_alpha = smoothstep(0.0, edge_softness, silhouette_dx);

	float vert_alpha = smoothstep(0.0, top_fade, uv.y) * smoothstep(0.0, bottom_fade, 1.0 - uv.y);
	float silhouette_alpha = edge_alpha * vert_alpha;

	// === Schaum ===
	// 1. Hauptstreifen
	float foam_streaks = texture(foam_pattern, uv_a * vec2(1.0, 0.6)).r;
	float main_foam = smoothstep(1.0 - foam_density, 1.0, foam_streaks * n_a);

	// 2. Edge-Foam (folgt jetzt der ausgefransten Silhouette)
	float edge_band = (1.0 - smoothstep(edge_softness * 0.3, edge_softness * 1.2, silhouette_dx))
	                * smoothstep(0.0, edge_softness * 0.4, silhouette_dx);
	float edge_foam = edge_band * (0.4 + n_b * 0.8);

	// 3. Top Foam
	float top_foam = smoothstep(top_foam_band, 0.0, uv.y) * (0.6 + n_a * 0.5);

	// 4. Bottom Foam
	float bot_foam = smoothstep(1.0 - bottom_foam_band, 1.0, uv.y) * (0.7 + n_b * 0.4);

	float foam = clamp(main_foam + edge_foam * 0.7 + top_foam + bot_foam, 0.0, 1.0);
	vec3 final_col = mix(water, foam_color.rgb, foam);

	// === Backlight (subtler innerer Glow für Tiefe) ===
	float backlight = (1.0 - foam) * smoothstep(0.4, 0.0, uv.y) * backlight_strength;

	// Normal map blend
	vec3 n1 = texture(texture_normal, uv_a * 0.8).rgb;
	vec3 n2 = texture(texture_normal, uv_b * 0.5).rgb;
	vec3 normal_blend = mix(n1, n2, 0.5);

	// Alpha: Wasser-Transparenz, Schaum opak, alles mit Silhouette multipliziert
	float water_alpha = mix(opacity_base, opacity_foam, foam);
	float final_alpha = water_alpha * silhouette_alpha;

	ALBEDO     = final_col;
	EMISSION   = foam * foam_color.rgb * foam_emission * 0.4 + color_top.rgb * backlight * 1.3;
	NORMAL_MAP = normal_blend;
	METALLIC   = metallic;
	ROUGHNESS  = mix(roughness * 2.0, roughness, foam);
	ALPHA      = final_alpha;
}