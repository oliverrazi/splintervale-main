shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec3 albedo : source_color;
uniform vec3 albedo2 : source_color;

uniform float metallic : hint_range(0.0, 1.0) = 0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform sampler2D wave;
uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform vec2 wave_direction = vec2(2.0,0.0);
uniform vec2 wave_direction2 = vec2(2.0,0.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.005;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.15;
//Varying variable
varying float height;
varying vec3 world_pos;

uniform vec4 color_deep: source_color;
uniform vec4 color_shallow: source_color;
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;
uniform float water_transparency: hint_range(0.0, 1.0, 0.01) = 0.0;

uniform float refreaction_strength: hint_range(0.0, 8.0, 0.001) = 0.5;


uniform float edge_scale = 0.1;
uniform float near = 1.0;
uniform float far = 100.0;
uniform vec3 edge_color : source_color;





float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float edge(float depth) {
	depth = 2.0 * depth - 1.0;
	return near * far / (far + depth * (near -far));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = texture(wave, world_pos.xz / noise_scale + TIME * time_scale).r;
	VERTEX.y += height * height_scale;
}

void fragment() {

    // --- Depth calculation (wie bei dir) ---
    float depth_texture = texture(DEPTH_TEXTURE, SCREEN_UV).r * 2.0 - 1.0;
    float depth = PROJECTION_MATRIX[3][2] / (depth_texture + PROJECTION_MATRIX[2][2]);

    float depth_blend = exp((depth + VERTEX.z + depth_offset) * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    // --- Edge detection (wie bei dir) ---
    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos = edge(FRAGCOORD.z);
    float z_dif = z_depth - z_pos;

    // --- Normal maps (wie bei dir) ---
    vec2 time = (TIME * wave_direction) * time_scale;
    vec2 time2 = (TIME * wave_direction2) * time_scale;
    vec3 normal_blend = mix(
        texture(texture_normal,  world_pos.xz + time).rgb,
        texture(texture_normal2, UV + time2).rgb,
        0.5
    );

    // --- Fresnel + surface color (wie bei dir, nur Name angepasst) ---
    float fr = fresnel(5.0, NORMAL, VIEW);
    vec3 surface_color = mix(albedo, albedo2, fr);

    // --- Depth color + screen color (wie bei dir, aber refraction-ready) ---
    vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, depth_blend_power);

    // Transparenz soll typischerweise in flachem Wasser stärker sein als in tiefem Wasser.
    // shallow_factor: 1 = sehr flach, 0 = tief
    float shallow_factor = 1.0 - depth_blend_power;

    // Effektive Transparenz: water_transparency steuert das Maximum,
    // shallow_factor sorgt dafür, dass tiefes Wasser weniger durchsichtig wird.
    float t = clamp(water_transparency * shallow_factor, 0.0, 1.0);

    // Optional: Screen-Space-Refraction (leichte UV-Verzerrung über Normalmap)
    // Wenn du nur Transparenz willst: ref_uv = SCREEN_UV lassen.
    vec2 ref_uv = SCREEN_UV + (normal_blend.xy * 2.0 - 1.0) * (refreaction_strength * 0.02) * t;

    // Hintergrund (refracted) – LOD wie gehabt, aber über ref_uv
    vec3 screen_color = textureLod(SCREEN_TEXTURE, ref_uv, depth_blend_power * 2.5).rgb;

    // Deine Farbmischung beibehalten (leicht gestrafft)
    vec3 water_color = mix(screen_color * depth_color, depth_color * 0.25, depth_blend_power * 0.5);

    // Edge/Intersection coloring
    vec3 depth_color_adj = mix(edge_color, water_color, step(edge_scale, z_dif));

    // Final shading
    ALBEDO = clamp(surface_color + depth_color_adj, vec3(0.0), vec3(1.0));
    METALLIC = metallic;
    ROUGHNESS = roughness;
    NORMAL_MAP = normal_blend;

    // --- Transparenz: 1 = opak, 0 = unsichtbar ---
    // t = "wie viel man durchsehen will"
    ALPHA = 1.0 - t;
	ALPHA = 0.8;
}



//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
