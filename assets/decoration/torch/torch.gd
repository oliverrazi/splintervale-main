class_name Torch
extends Node3D
## Verdrahtet Flamme und Licht einer Fackel: gemeinsamer Phase-Offset,
## Noise-basiertes Flackern (kein Zufallszittern), optionales Farb-Atmen.

@export var flame: MeshInstance3D
@export var light: OmniLight3D

@export_group("Flicker")
## Grundhelligkeit, um die herum geflackert wird.
@export var base_energy: float = 1.2
## Flacker-Anteil: 0.15 = ±15% um base_energy.
@export_range(0.0, 1.0) var flicker_amount: float = 0.15
## Geschwindigkeit des Flackerns. Sollte gefühlt zum scroll_speed
## des Flame-Shaders passen (gleiche Größenordnung).
@export var flicker_speed: float = 1.3
## Zweite, schnellere Flacker-Schicht für kurzes Züngeln (0 = aus).
@export_range(0.0, 1.0) var shimmer_amount: float = 0.06

@export_group("Color Breathing")
## Leichte Farbverschiebung beim Flackern (hell = heißer/weißer).
@export var color_low: Color = Color(1.0, 0.6, 0.3)
@export var color_high: Color = Color(1.0, 0.82, 0.55)

var _phase: float = 0.0
var _noise := FastNoiseLite.new()

func _ready() -> void:
	_phase = randf() * 100.0

	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	_noise.seed = 1337  # fester Seed: Charakter kommt aus _phase, nicht aus dem Seed

	if flame != null:
		flame.set_instance_shader_parameter("phase_offset", _phase)
	if light != null:
		light.light_energy = base_energy

func _process(_delta: float) -> void:
	if light == null:
		return

	var t: float = Time.get_ticks_msec() * 0.001 * flicker_speed + _phase

	# Zwei Noise-Oktaven: langsames Atmen + schnelles Züngeln.
	# get_noise_1d liefert ~[-1, 1], weich und ohne Sprünge.
	var slow: float = _noise.get_noise_1d(t)
	var fast: float = _noise.get_noise_1d(t * 4.7 + 31.0)
	var f: float = slow * flicker_amount + fast * shimmer_amount

	light.light_energy = base_energy * (1.0 + f)

	# Farb-Atmen: f von [-max, +max] auf [0, 1] mappen
	var max_f: float = flicker_amount + shimmer_amount
	if max_f > 0.001:
		var k: float = clampf(f / max_f * 0.5 + 0.5, 0.0, 1.0)
		light.light_color = color_low.lerp(color_high, k)
