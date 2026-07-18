shader_type spatial;
render_mode cull_disabled;

// Riss-Textur-Overlay über dem Boden-Albedo.
// Die Risse wachsen während der Warnphase von der Mitte nach außen.

uniform sampler2D base_texture : source_color, hint_default_white;
uniform vec4 base_color : source_color = vec4(0.5, 0.47, 0.43, 1.0);

uniform sampler2D crack_texture : source_color, hint_default_white;
uniform float crack_darkness : hint_range(0.0, 1.0) = 0.85;

uniform bool crack_uses_alpha = false;

// Ausbreitung
uniform float crack_progress : hint_range(0.0, 1.0) = 0.0;
uniform float base_crack_progress : hint_range(0.0, 1.0) = 0.35;
uniform vec2 crack_center = vec2(0.5, 0.5);

uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D normal_texture : hint_normal;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform bool use_normal_map = false;

void fragment() {
	vec3 albedo = texture(base_texture, UV).rgb * base_color.rgb;

	// Riss-Textur über die NORMALISIERTEN UVs (UV2) → füllt den Deckel 0-1
	vec4 crack_tex = texture(crack_texture, UV2);

	// Riss-Maske: echter Alpha ODER invertierte Helligkeit
	float crack_mask;
	if (crack_uses_alpha) {
		crack_mask = crack_tex.a;
	} else {
		// dunkle Risse auf hellem Grund → dunkel = Riss
		float luma = dot(crack_tex.rgb, vec3(0.299, 0.587, 0.114));
		crack_mask = 1.0 - luma;
	}

	// Ausbreitung von der Mitte
	float active_progress = max(crack_progress, base_crack_progress);
	float dist_from_center = length(UV2 - crack_center);
	float reach = smoothstep(active_progress - 0.15, active_progress, dist_from_center);
	crack_mask *= (1.0 - reach);

	// Risse abdunkeln
	albedo = mix(albedo, albedo * (1.0 - crack_darkness), crack_mask);
	
	if (use_normal_map) {
	    NORMAL_MAP = texture(normal_texture, UV).rgb;
	    NORMAL_MAP_DEPTH = normal_scale;
	}


	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}