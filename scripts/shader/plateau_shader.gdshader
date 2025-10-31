shader_type spatial;

uniform sampler2D grass_texture : source_color;
uniform sampler2D earth_texture : source_color;
uniform float texture_scale = 1.0;
uniform float grass_overhang = 0.05;
uniform float plateau_height = 5.0;

varying vec3 world_normal;
varying vec3 world_position;
varying vec3 local_position;
varying vec3 model_origin;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX;
	model_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	// === GRAS vs ERDE Entscheidung ===
	
	// Methode 1: Normale (zeigt nach oben?)
	float up_factor = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	
	// Methode 2: Absolute Höhe (nah an der Oberseite?)
	float height_from_top = plateau_height - local_position.y;
	
	// VEREINFACHTE Grass Overhang Logik
	float grass_height_factor = 1.0 - smoothstep(0.0, grass_overhang * 2.0, height_from_top);
	
	// Normal muss nach oben zeigen (> 85 Grad)
	float grass_normal_factor = smoothstep(0.85, 0.95, up_factor);
	
	// BEIDE müssen erfüllt sein
	float is_grass = grass_height_factor * grass_normal_factor;
	
	// === TEXTUR UVs ===
	vec2 grass_uv = world_position.xz * texture_scale * 0.5;
	
	// Erde: Triplanar Mapping
	vec3 blend_weights = abs(world_normal);
	blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);
	
	vec2 uv_x = world_position.zy * texture_scale * 0.1;
	vec2 uv_y = world_position.xz * texture_scale * 0.2;
	vec2 uv_z = world_position.xy * texture_scale * 0.2;
	
	vec4 earth_x = texture(earth_texture, uv_x);
	vec4 earth_y = texture(earth_texture, uv_y);
	vec4 earth_z = texture(earth_texture, uv_z);
	
	vec4 earth_color = earth_x * blend_weights.x + 
	                   earth_y * blend_weights.y + 
	                   earth_z * blend_weights.z;
	
	vec4 grass_color = texture(grass_texture, grass_uv);
	
	// === FINALES MISCHEN ===
	// WICHTIG: Verwende is_grass direkt als Alpha, nicht als smoothstep
	// Mix: 0 = earth, 1 = grass
	vec4 final_color = mix(earth_color, grass_color, is_grass);
	
	ALBEDO = final_color.rgb;
	
	// DEBUG: Uncomment um is_grass als Helligkeit zu sehen
	// ALBEDO = vec3(is_grass);
}
