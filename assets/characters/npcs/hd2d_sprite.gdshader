shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec2 frame_size = vec2(1.0);
uniform vec2 frame_offset = vec2(0.0);
uniform bool flip_h = false;

uniform float screen_y = 0.5;
uniform float correction_strength = 0.6;

void vertex() {
	// Weltposition des Sprite-Ursprungs
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	
	// Richtung zur Kamera (nur horizontal)
	vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
	vec3 to_cam_flat = normalize(vec3(to_cam.x, 0.0, to_cam.z));
	
	// Basis-Vektoren für Y-Billboard
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam_flat));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 forward = to_cam_flat;
	
	// Vertex-Position im Billboard-Space
	vec3 local_pos = right * VERTEX.x + up * VERTEX.y;
	
	// === DIE MAGISCHE KORREKTUR ===
	// screen_y: 0 = oben, 1 = unten
	// Je weiter unten, desto mehr "shear" nach hinten
	float shear = screen_y * correction_strength;
	
	// Obere Vertices nach hinten schieben, untere nach vorne
	// VERTEX.y ist -0.5 (unten) bis +0.5 (oben) bei QuadMesh
	local_pos += forward * (VERTEX.y * shear * -1.5);
	
	VERTEX = local_pos;
	
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right, 0.0),
		vec4(up, 0.0),
		vec4(forward, 0.0),
		vec4(world_pos, 1.0)
	);
}

void fragment() {
	vec2 uv = UV;
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	uv = uv * frame_size + frame_offset;
	
	vec4 col = texture(sprite_texture, uv);
	if (col.a < 0.1) discard;
	
	ALBEDO = col.rgb;
	ALPHA = col.a;
}