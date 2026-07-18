shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
// =============================================================
//  Resonance Mote  – weicher Lichtpunkt (Draw Pass der Particles)
//
//  Gedacht als Material auf dem QuadMesh-Draw-Pass eines
//  GPUParticles3D. Billboarded im Vertex-Shader, radialer
//  Soft-Falloff statt Textur. COLOR.a kommt aus der Color Ramp
//  des ParticleProcessMaterial (Fade-In/Out über Lifetime).
// =============================================================
uniform vec4  mote_color : source_color = vec4(0.80, 0.92, 1.0, 1.0);
uniform float mote_intensity : hint_range(0.0, 8.0) = 2.5;

void vertex() {
	// Billboard, Skalierung des Partikels bleibt erhalten
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	a *= a;   // weicherer Kern
	ALBEDO = mote_color.rgb * mote_intensity;
	ALPHA = a * COLOR.a;
}
