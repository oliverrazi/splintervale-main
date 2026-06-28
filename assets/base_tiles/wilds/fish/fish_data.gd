## FishData
##
## Reine Datenstruktur pro Fisch — KEIN Node, kein _process.
## Der FishManager besitzt diese Objekte und treibt sie zentral.

class_name FishData
extends RefCounted

enum State {
	IDLE,    ## steht fast still, leichtes Bobbing, langsame Flossen-Anim
	CRUISE,  ## normales Schwimmen
	DART,    ## kurzer schneller Burst (ruckartig)
}

# --- Verhalten ---
var schooling: bool = false          ## true = Alignment+Cohesion mit gleichem Schwarm

# --- Heimat-Anker (vom Marker) ---
var home: Vector3 = Vector3.ZERO     ## Marker-Position; Y davon = feste Schwebehöhe
var home_radius: float = 3.0         ## Streifradius; darüber greift der Home-Pull

# --- Bewegung (XZ schwimmt, Y ist feste Höhe + Bobbing) ---
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD

# --- Bobbing ---
var bob_phase: float = 0.0

# --- State-Machine ---
var state: int = State.CRUISE
var state_timer: float = 0.0
var dart_dir: Vector3 = Vector3.FORWARD

# --- Animation ---
var anim_time: float = 0.0
var sprite: SmoothPixelSprite3D = null

# --- Raycast-Staffelung ---
var ray_offset: int = 0
var last_avoid: Vector3 = Vector3.ZERO  ## letzter Wandvermeidungs-Vektor (zwischen Casts gehalten)
var near_wall: bool = false             ## true = casted jeden Frame (nah an Wand)
