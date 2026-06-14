@tool
extends Resource
class_name ScatterProfile
## Beschreibt einen Billboard-Pflanzentyp (Gras, Blumen, Farn, ...) der vom
## GrassSystem im Shape-Polygon verstreut wird. Jedes Profil erzeugt pro
## sichtbarem Chunk ein eigenes MultiMesh, damit unterschiedliche Texturen /
## Wind-Parameter sauber getrennt bleiben.
##
## Gewichtung: density_weight bestimmt, welchen Anteil der Gesamt-Instanzen
## dieses Profil bekommt (relativ zu anderen Profilen in derselben Liste).
@export var profile_name: String = "Grass"
## Textur des Billboards (Alpha-Kanal = Form). source_color, repeat_disable.
@export var texture: Texture2D
## Anteil an der Gesamtdichte relativ zu den anderen Profilen.
## Zwei Profile mit 1.0 und 0.2 -> 83% Gras, 17% Blumen.
@export var density_weight: float = 1.0
@export_group("Scale")
## Basis-Groesse (x = Breite, y = Hoehe) in Meter.
@export var scale: Vector2 = Vector2(0.02, 0.2)
## Zufaellige Groessenvariation pro Instanz (+/- Faktor).
@export var scale_variation: float = 0.5
## Wie stark dieses Profil bei Distanz-LOD ausgeduennt werden darf.
## 1.0 = wird voll mitgezaehlt, hoehere Werte = wird in der Ferne staerker reduziert.
## Blumen z.B. hoeher setzen, da sie in der Ferne weniger wichtig sind.
@export var lod_thin_bias: float = 1.0
@export_group("Color (Per-Instance)")
## Zufaellige Helligkeitsvariation pro Instanz (+/- Faktor).
@export var color_variation: float = 1.0
## Kuehler Grundton (bei Noise = 0).
@export var noise_color_cool: Color = Color(0.85, 1.05, 0.8, 1.0)
## Warmer Ton (bei Noise = 1).
@export var noise_color_warm: Color = Color(1.15, 1.1, 0.7, 1.0)
## Wie stark der Noise zwischen cool/warm blendet.
@export var noise_color_strength: float = 0.5
## Frequenz des Farb-Noise (kleiner = groessere Farbflaechen).
@export var noise_frequency: float = 0.15

@export_group("Shader Tint (Per-Fragment)")
## Die folgenden Werte ueberschreiben die Toenung IM SHADER pro Profil.
## Fuer Blumen typisch: alles auf Weiss / 0, damit die reine Texturfarbe kommt
## und NICHT der Gras-Gelbstich. Fuer Gras die gruenlichen Defaults belassen.
## Heller Toenungs-Pol (bei Noise hoch). Weiss = keine Toenung.
@export var tint_a: Color = Color(0.85, 1.0, 0.75)
## Dunkler/waermerer Toenungs-Pol (bei Noise niedrig). Weiss = keine Toenung.
@export var tint_b: Color = Color(0.9, 0.8, 0.1)
## Helligkeitsvariation im Shader (0 = aus). Blumen: ruhig etwas Variation ok.
@export_range(0.0, 0.5) var shader_brightness_variation: float = 0.2
## Saettigungsvariation im Shader (0 = aus). Blumen: meist 0 sinnvoll.
@export_range(0.0, 0.5) var shader_saturation_variation: float = 0.15
## Skala des Shader-Farbnoise (Fleckengroesse). Kleiner = groessere Flecken.
@export var shader_color_noise_scale: float = 0.05

@export_group("Height Tinting")
## Spitzen-Toenung (heller). Fuer Blumen meist neutral lassen.
@export var tip_tint: Color = Color(1.1, 1.15, 0.9)
@export_range(0.0, 1.0) var tip_tint_strength: float = 0.25
## Basis-Toenung (dunkler am Fuss). Erzeugt Tiefe.
@export var base_tint: Color = Color(0.4, 0.55, 0.3)
@export_range(0.0, 1.0) var base_tint_strength: float = 0.35
## Ambient Occlusion am Boden.
@export_range(0.0, 1.0) var ao_strength: float = 0.4

@export_group("Wind")
## Multiplikator auf die globale Windstaerke des GrassSystem.
## Blumen mit steifem Stiel -> niedriger, hohes Gras -> 1.0+.
@export var wind_multiplier: float = 1.0
@export_group("Placement")
## Hoehen-Multiplikator am Polygon-Rand (Edge-Falloff). 1.0 = kein Effekt.
@export var edge_min_height: float = 0.2

## Liefert ein reines Dictionary fuer den Worker-Thread (kein Resource-Zugriff
## ausserhalb des Main-Threads -> wir kopieren alle Werte raus).
func snapshot() -> Dictionary:
	return {
		"profile_name": profile_name,
		"density_weight": max(density_weight, 0.0),
		"scale": scale,
		"scale_variation": scale_variation,
		"lod_thin_bias": max(lod_thin_bias, 0.01),
		"color_variation": color_variation,
		"noise_color_cool": noise_color_cool,
		"noise_color_warm": noise_color_warm,
		"noise_color_strength": noise_color_strength,
		"noise_frequency": noise_frequency,
		"wind_multiplier": wind_multiplier,
		"edge_min_height": edge_min_height,
	}


## Setzt die profil-spezifischen Shader-Parameter auf ein Material.
## Wird vom GrassSystem in _rebuild_materials pro Profil aufgerufen, damit
## jedes Profil (Gras, Blume, ...) seine eigene Toenung bekommt.
func apply_shader_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("color_tint_a", Vector3(tint_a.r, tint_a.g, tint_a.b))
	mat.set_shader_parameter("color_tint_b", Vector3(tint_b.r, tint_b.g, tint_b.b))
	mat.set_shader_parameter("brightness_variation", shader_brightness_variation)
	mat.set_shader_parameter("saturation_variation", shader_saturation_variation)
	mat.set_shader_parameter("color_noise_scale", shader_color_noise_scale)
	mat.set_shader_parameter("tip_tint", Vector3(tip_tint.r, tip_tint.g, tip_tint.b))
	mat.set_shader_parameter("tip_tint_strength", tip_tint_strength)
	mat.set_shader_parameter("base_tint", Vector3(base_tint.r, base_tint.g, base_tint.b))
	mat.set_shader_parameter("base_tint_strength", base_tint_strength)
	mat.set_shader_parameter("ao_strength", ao_strength)
