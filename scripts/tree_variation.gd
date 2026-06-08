class_name TreeVariation
extends RefCounted

# Erzeugt einen stabilen Pseudo-Random-Wert 0..1 aus einer Position + Salt.
# Salt trennt die drei Achsen (Hue/Brightness/Saturation) voneinander, damit
# sie nicht korrelieren (sonst sähen helle Bäume immer auch verschoben aus).
static func _hash01(pos: Vector3, salt: float) -> float:
	# Großzügige Frequenzen, damit benachbarte Bäume sichtbar verschieden sind.
	var v := sin(pos.x * 12.9898 + pos.z * 78.233 + pos.y * 37.719 + salt * 53.123) * 43758.5453
	return v - floor(v)

# Gibt die 4 Custom-Data-Floats (0..1) für das MultiMesh zurück.
# r=Hue, g=Brightness, b=Saturation, a=frei (Wind-Phase etc.)
static func custom_data_for(pos: Vector3) -> Color:
	return Color(
		_hash01(pos, 0.0),   # Hue-Shift
		_hash01(pos, 17.0),  # Brightness
		_hash01(pos, 41.0),  # Saturation
		_hash01(pos, 91.0)   # frei
	)

static func instance_color_for(pos: Vector3, warmth_range: float = 0.74, brightness_range: float = 0.6) -> Color:
	var bri := _hash01(pos, 17.0) * 2.0 - 1.0
	var warm := _hash01(pos, 41.0) * 2.0 - 1.0
	var brightness := 1.0 + bri * brightness_range
	var r := brightness * (1.0 + warm * warmth_range)
	var g := brightness
	var b := brightness * (1.0 - warm * warmth_range)
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0)

# Berechnet die FERTIGE Tönungsfarbe für eine echte Tree-Scene, sodass sie
# zum MultiMesh-Shader passt. Muss dieselbe Mathematik wie der Shader nutzen!
# ranges entsprechen den Shader-Uniforms.
static func tint_for_real_scene(
		pos: Vector3,
		hue_range: float = 0.06,
		brightness_range: float = 0.25,
		saturation_range: float = 0.30,
		season_hue_shift: float = 0.0
	) -> Dictionary:
	var cd := custom_data_for(pos)
	var hue_signed := cd.r * 2.0 - 1.0
	var bri_signed := cd.g * 2.0 - 1.0
	var sat_signed := cd.b * 2.0 - 1.0
	return {
		"hue_shift": hue_signed * hue_range + season_hue_shift,
		"brightness_mul": 1.0 + bri_signed * brightness_range,
		"saturation_mul": 1.0 + sat_signed * saturation_range,
	}

# Wendet eine HSV-Variation auf eine Basisfarbe an (für echte Scenes, falls du
# das StandardMaterial3D-Albedo direkt tönen willst statt eines Shaders).
static func apply_hsv_variation(base: Color, variation: Dictionary) -> Color:
	var h := base.h
	var s := base.s
	var v := base.v
	h = fposmod(h + variation.hue_shift, 1.0)
	s = clampf(s * variation.saturation_mul, 0.0, 1.0)
	v = clampf(v * variation.brightness_mul, 0.0, 1.0)
	return Color.from_hsv(h, s, v, base.a)
