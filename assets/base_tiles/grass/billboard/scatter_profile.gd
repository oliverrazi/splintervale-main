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
## Zwei Profile mit 1.0 und 0.2 → 83% Gras, 17% Blumen.
@export var density_weight: float = 1.0

@export_group("Scale")
## Basis-Größe (x = Breite, y = Höhe) in Meter.
@export var scale: Vector2 = Vector2(0.02, 0.2)
## Zufällige Größenvariation pro Instanz (± Faktor).
@export var scale_variation: float = 0.5
## Wie stark dieses Profil bei Distanz-LOD ausgedünnt werden darf.
## 1.0 = wird voll mitgezählt, höhere Werte = wird in der Ferne stärker reduziert.
## Blumen z.B. höher setzen, da sie in der Ferne weniger wichtig sind.
@export var lod_thin_bias: float = 1.0

@export_group("Color")
## Zufällige Helligkeitsvariation pro Instanz (± Faktor).
@export var color_variation: float = 1.0
## Kühler Grundton (bei Noise = 0).
@export var noise_color_cool: Color = Color(0.85, 1.05, 0.8, 1.0)
## Warmer Ton (bei Noise = 1).
@export var noise_color_warm: Color = Color(1.15, 1.1, 0.7, 1.0)
## Wie stark der Noise zwischen cool/warm blendet.
@export var noise_color_strength: float = 0.5
## Frequenz des Farb-Noise (kleiner = größere Farbflächen).
@export var noise_frequency: float = 0.15

@export_group("Wind")
## Multiplikator auf die globale Windstärke des GrassSystem.
## Blumen mit steifem Stiel → niedriger, hohes Gras → 1.0+.
@export var wind_multiplier: float = 1.0

@export_group("Placement")
## Höhen-Multiplikator am Polygon-Rand (Edge-Falloff). 1.0 = kein Effekt.
@export var edge_min_height: float = 0.2


## Liefert ein reines Dictionary für den Worker-Thread (kein Resource-Zugriff
## außerhalb des Main-Threads → wir kopieren alle Werte raus).
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
