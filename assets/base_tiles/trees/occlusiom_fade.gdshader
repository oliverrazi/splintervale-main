shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

uniform sampler2D albedo_texture : source_color;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Occlusion-Parameter
uniform vec3 player_position;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float circle_radius : hint_range(0.1, 5.0) = 1.2;
uniform float circle_softness : hint_range(0.1, 3.0) = 0.6;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.2;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	tex *= albedo_color;
	
	// Original Alpha-Cutout
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	
	ALBEDO = tex.rgb;
	
	// Distanz zum Spieler (XZ-Ebene)
	float dist = distance(world_position.xz, player_position.xz);
	
	// Kreis-Maske: 0 = nah am Spieler, 1 = weit weg
	float circle_mask = smoothstep(circle_radius - circle_softness, circle_radius + circle_softness, dist);
	
	// Alpha: Im Kreis = min_alpha, außerhalb = 1.0
	// fade steuert ob Effekt aktiv ist
	float target_alpha = mix(min_alpha, 1.0, circle_mask);
	float final_alpha = mix(1.0, target_alpha, fade);
	
	ALPHA = tex.a * final_alpha;
}