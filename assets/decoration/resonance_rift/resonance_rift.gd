@tool
extends Node3D
class_name ResonanceRift
# =============================================================
#  ResonanceRift v2  – Controller für einen Resonanzriss
#
#  Änderungen ggü. v1:
#   - Crack-Plane entfällt (echte 3D-Risse im Level-Mesh).
#     Der Node "Crack" ist jetzt OPTIONAL (get_node_or_null),
#     falls doch mal ein Boden-Glow gewünscht ist.
#
#  Treibt einen gemeinsamen "Herzschlag" (Puls) und schiebt ihn
#  synchron in:
#   - Beam-Shader   (instance uniform "pulse")
#   - OmniLight3D   (light_energy)
#   - Crack-Shader  (nur falls Node vorhanden)
#
#  Erwarteter Szenenbaum:
#   ResonanceRift (dieses Script)
#   ├── Beam      (MeshInstance3D, resonance_beam.gdshader)
#   ├── Motes     (GPUParticles3D)                        [optional]
#   ├── RiftLight (OmniLight3D)
#   └── Crack     (MeshInstance3D)                        [optional]
# =============================================================

## Grund-Energie des OmniLight. Das ist der "Knall"-Regler.
@export var light_energy_base: float = 3.0
## Langsames Atmen: Geschwindigkeit des Haupt-Pulses.
@export var pulse_speed: float = 0.6
## Wie stark der Puls schwankt (0.35 = ±35 %).
@export_range(0.0, 1.0) var pulse_strength: float = 0.35
## Feines, schnelles Flackern nur auf dem Licht (0 = aus).
@export var light_flicker: float = 0.4

@onready var _beam: MeshInstance3D = $Beam
@onready var _light: OmniLight3D = $RiftLight
@onready var _crack: MeshInstance3D = get_node_or_null("Crack")

var _noise := FastNoiseLite.new()
var _t: float = 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	# Jede Instanz startet phasenversetzt -> Risse pulsieren nie synchron.
	_t = randf() * 1000.0


func _process(delta: float) -> void:
	_t += delta

	# Langsames Atmen (-1..1) + schnelles feines Flackern.
	var slow: float = _noise.get_noise_1d(_t * pulse_speed * 10.0)
	var fast: float = _noise.get_noise_1d(_t * 70.0 + 500.0)

	var pulse: float = 1.0 + slow * pulse_strength

	_beam.set_instance_shader_parameter("pulse", pulse)
	if _crack != null:
		_crack.set_instance_shader_parameter("pulse", pulse)
	_light.light_energy = maxf(light_energy_base * pulse + fast * light_flicker, 0.0)
