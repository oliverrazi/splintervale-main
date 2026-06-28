shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 uv_scale = vec3(1.0, 1.0, 1.0);

// === Wetness Globals ===
global uniform vec3 waterfall_pos_0;
global uniform vec3 waterfall_pos_1;
global uniform vec3 waterfall_pos_2;
global uniform float waterfall_radius_0;
global uniform float waterfall_radius_1;
global uniform float waterfall_radius_2;
global uniform float waterfall_height_0;
global uniform float waterfall_height_1;
global uniform float waterfall_height_2;
global uniform int waterfall_count;

uniform float wet_roughness     : hint_range(0.0, 1.0) = 0.25;
uniform float wet_albedo_mult   : hint_range(0.0, 1.0) = 0.55;
uniform float wet_metallic      : hint_range(0.0, 1.0) = 0.1;
uniform float wet_falloff_power : hint_range(0.5, 4.0) = 1.5;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float wetness_from(vec3 wf_pos, float wf_radius, float wf_height, vec3 world_pos) {
	float closest_y = clamp(world_pos.y, wf_pos.y, wf_pos.y + wf_height);
	vec3 closest_point = vec3(wf_pos.x, closest_y, wf_pos.z);
	float dist = distance(world_pos, closest_point);
	float w = 1.0 - smoothstep(wf_radius * 0.3, wf_radius, dist);
	return pow(w, wet_falloff_power);
}

float calc_wetness(vec3 world_pos) {
	float max_wet = 0.0;
	if (waterfall_count > 0) max_wet = max(max_wet, wetness_from(waterfall_pos_0, waterfall_radius_0, waterfall_height_0, world_pos));
	if (waterfall_count > 1) max_wet = max(max_wet, wetness_from(waterfall_pos_1, waterfall_radius_1, waterfall_height_1, world_pos));
	if (waterfall_count > 2) max_wet = max(max_wet, wetness_from(waterfall_pos_2, waterfall_radius_2, waterfall_height_2, world_pos));
	return clamp(max_wet, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * uv_scale.xy;
	
	vec4 albedo_sample = texture(albedo_tex, uv) * albedo_color;
	vec3 normal_sample = texture(normal_tex, uv).rgb;
	
	float wetness = calc_wetness(world_position);
	
	vec3 final_albedo  = albedo_sample.rgb * mix(1.0, wet_albedo_mult, wetness);
	float final_roughness = mix(roughness_base, wet_roughness, wetness);
	float final_metallic  = mix(metallic_base, wet_metallic, wetness);
	
	ALBEDO     = final_albedo;
	ROUGHNESS  = final_roughness;
	METALLIC   = final_metallic;
	NORMAL_MAP = normal_sample;
	NORMAL_MAP_DEPTH = normal_strength;
}