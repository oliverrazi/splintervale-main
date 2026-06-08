shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform sampler2D streak_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mote_tex   : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 ray_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform float intensity : hint_range(0.0, 4.0, 0.05) = 2.0;

// Tiling & Bewegung
uniform vec2  streak_tiling = vec2(1.0, 1.0);
uniform vec2  mote_tiling   = vec2(2.5, 4.0);
uniform float mote_speed : hint_range(0.0, 1.0, 0.005) = 0.08;
uniform float mote_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

// Soft Edges
uniform float fade_top    : hint_range(0.0, 0.5, 0.01) = 0.35;  // war 0.05 – jetzt sehr lang
uniform float fade_bottom : hint_range(0.0, 0.5, 0.01) = 0.30;
uniform float edge_softness : hint_range(0.0, 0.5, 0.01) = 0.30;

// Fresnel: bei Schrägsicht ausblenden (sonst sieht man den Quad als Plane)
uniform float fresnel_power    : hint_range(1.0, 8.0, 0.1) = 2.5;
uniform float fresnel_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
	vec2 uv = UV;
	
	// Vertikale Streifen (statisch)
	float streaks = texture(streak_tex, uv * streak_tiling).r;
	streaks = pow(streaks, 1.4);
	
	// Staubpartikel: animiert, langsam nach unten driftend
	vec2 mote_uv = uv * mote_tiling + vec2(0.0, -TIME * mote_speed);
	float motes = texture(mote_tex, mote_uv).r * mote_strength;
	
	// Soft horizontal Edges
	float edge_h = smoothstep(0.0, edge_softness, uv.x) 
	             * smoothstep(0.0, edge_softness, 1.0 - uv.x);
	
	// Vertikales Fading: oben kurz, unten lang (Strahl verblasst nach unten)
	float fade_t = smoothstep(0.0, fade_top, uv.y);
	float fade_b = smoothstep(0.0, fade_bottom, 1.0 - uv.y);
	
	// Fresnel: bei flachem Sichtwinkel fade-out
	float fresnel = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	fresnel = pow(fresnel, fresnel_power);
	float view_alpha = 1.0 - fresnel * fresnel_strength;
	
	float mask = (streaks + motes) * edge_h * fade_t * fade_b * view_alpha;
	
	ALBEDO = ray_color.rgb * intensity;
	ALPHA  = mask;
}